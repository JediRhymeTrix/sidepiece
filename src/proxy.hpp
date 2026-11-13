#pragma once
using Headers = std::vector<std::pair<string, string>>;
static bool headerName(const string &s) {
    if (s.empty())
        return false;
    for (unsigned char c : s)
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
              string("!#$%&'*+-.^_`|~").find((char)c) != string::npos))
            return false;
    return true;
}
static Headers parseHeaders(const string &s) {
    Headers out;
    size_t p = 0;
    while (p < s.size()) {
        size_t e = s.find("\r\n", p);
        require(e != string::npos, "invalid headers");
        if (e == p) {
            require(e + 2 == s.size(), "trailing headers");
            break;
        }
        string line = s.substr(p, e - p);
        size_t c = line.find(':');
        require(c != string::npos && headerName(line.substr(0, c)), "invalid header name");
        string value = trim(line.substr(c + 1));
        for (unsigned char ch : value)
            require(ch >= 32 || ch == '\t', "invalid header value");
        out.emplace_back(line.substr(0, c), value);
        require(out.size() <= 256, "too many headers");
        p = e + 2;
    }
    return out;
}
static string getHeader(const Headers &h, const string &name) {
    string out;
    int found = 0;
    for (const auto &x : h)
        if (lower(x.first) == name) {
            out = x.second;
            ++found;
        }
    require(found <= 1, "ambiguous singleton header");
    return out;
}
static std::set<string> hopHeaders(const Headers &h) {
    std::set<string> skip = {"connection",          "keep-alive", "proxy-authenticate",
                             "proxy-authorization", "te",         "trailer",
                             "transfer-encoding",   "upgrade",    "proxy-connection"};
    for (const auto &x : h)
        if (lower(x.first) == "connection") {
            size_t p = 0;
            for (;;) {
                size_t e = x.second.find(',', p);
                string name = lower(trim(x.second.substr(p, e == string::npos ? e : e - p)));
                require(headerName(name), "invalid connection header");
                skip.insert(name);
                if (e == string::npos)
                    break;
                p = e + 1;
            }
        }
    return skip;
}
static void sendBytes(SOCKET s, const char *p, size_t n) {
    while (n) {
        int sent = send(s, p, (int)std::min(n, (size_t)32768), 0);
        require(sent > 0, "client send failed");
        p += sent;
        n -= sent;
    }
}
static void sendString(SOCKET s, const string &b) { sendBytes(s, b.data(), b.size()); }
struct Reader {
    SOCKET s;
    string buffered;
    size_t pos = 0;
    ULONGLONG deadline = GetTickCount64() + 60000;
    explicit Reader(SOCKET v) : s(v) {}
    void fill() {
        require(GetTickCount64() < deadline, "request deadline");
        char b[8192];
        int n = recv(s, b, sizeof(b), 0);
        require(n > 0, "client read failed");
        if (pos) {
            buffered.erase(0, pos);
            pos = 0;
        }
        buffered.append(b, n);
    }
    string line(size_t max) {
        for (;;) {
            size_t e = buffered.find("\r\n", pos);
            if (e != string::npos) {
                require(e - pos <= max, "line too long");
                string r = buffered.substr(pos, e - pos);
                pos = e + 2;
                return r;
            }
            require(buffered.size() - pos <= max, "line too long");
            fill();
        }
    }
    size_t read(char *out, size_t max) {
        if (pos == buffered.size())
            fill();
        size_t n = std::min(max, buffered.size() - pos);
        memcpy(out, buffered.data() + pos, n);
        pos += n;
        return n;
    }
};
static string cors(bool origin) {
    return origin ? "Access-Control-Allow-Origin: "
                    "https://nvfile\r\nAccess-Control-Allow-Credentials: true\r\nVary: Origin\r\n"
                  : "";
}
static void reply(SOCKET s, int code, const string &body, bool origin = false,
                  const string &extra = {}) {
    sendString(
        s, "HTTP/1.1 " + std::to_string(code) +
               " Bridge\r\nConnection: close\r\nContent-Length: " + std::to_string(body.size()) +
               "\r\nContent-Type: application/json\r\n" + cors(origin) + extra + "\r\n" + body);
}
static HANDLE stopEvent = nullptr, drainedEvent = nullptr;
static std::atomic<unsigned> active{0};
static std::atomic<unsigned long long> requests{0}, rewrites{0};
static HINTERNET upstream = nullptr;
static bool upstreamSecure = true;
static Rules loadRules() {
    try {
        return parseRules(readFile(dir + L"\\config.json", 65536));
    } catch (...) {
        return {};
    }
}
static string health() {
    return "{\"ok\":true,\"native\":true,\"product\":\"GeForce Sidepiece\",\"pid\":" +
           std::to_string(GetCurrentProcessId()) +
           ",\"requests\":" + std::to_string(requests.load()) +
           ",\"rewrites\":" + std::to_string(rewrites.load()) + "}";
}
static bool decimal(const string &s, unsigned long long &value) {
    if (s.empty())
        return false;
    auto r = std::from_chars(s.data(), s.data() + s.size(), value);
    return r.ec == std::errc() && r.ptr == s.data() + s.size();
}
static void proxyRequest(SOCKET client, Reader &reader, const string &method, string target,
                         const Headers &headers, bool origin, bool &started) {
    auto skip = hopHeaders(headers);
    skip.insert("host");
    skip.insert("content-length");
    skip.insert("expect");
    skip.insert("x-forwarded-for");
    skip.insert("x-forwarded-host");
    skip.insert("x-forwarded-proto");
    skip.insert("forwarded");
    string length = getHeader(headers, "content-length"),
           encoding = lower(getHeader(headers, "transfer-encoding")),
           expect = lower(getHeader(headers, "expect"));
    unsigned long long total = 0;
    require(length.empty() || decimal(length, total), "invalid content length");
    require(total <= MAXDWORD, "body too large");
    require(encoding.empty() || encoding == "chunked", "unsupported transfer encoding");
    require(length.empty() || encoding.empty(), "ambiguous request framing");
    require(expect.empty() || expect == "100-continue", "unsupported expectation");
    if (expect == "100-continue")
        sendString(client, "HTTP/1.1 100 Continue\r\n\r\n");
    // ponytail: unknown-length uploads spool to an auto-deleted file (4 GiB ceiling), not RAM.
    // This keeps WinHTTP's known-length upload path simple; streaming chunked upload can replace it
    // if needed.
    wchar_t tempDir[MAX_PATH]{}, tempName[MAX_PATH]{};
    Handle spool;
    std::vector<char> transfer(16384);
    char *b = transfer.data();
    if (!encoding.empty()) {
        require(GetTempPathW(MAX_PATH, tempDir) > 0 &&
                    GetTempFileNameW(tempDir, L"nvb", 0, tempName) != 0,
                "cannot stage upload");
        spool.h = CreateFileW(tempName, GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
                              FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
        if (spool.h == INVALID_HANDLE_VALUE)
            DeleteFileW(tempName);
        require(spool.h != INVALID_HANDLE_VALUE, "cannot open upload spool");
        total = 0;
        for (;;) {
            string line = reader.line(8192);
            size_t semi = line.find(';');
            string size = line.substr(0, semi);
            unsigned long long count = 0;
            require(!size.empty() && size.size() <= 16, "bad chunk size");
            for (char c : size) {
                require(hex(c) >= 0 && count <= MAXDWORD / 16, "bad chunk size");
                count = count * 16 + hex(c);
            }
            require(total + count <= MAXDWORD, "upload too large");
            if (!count) {
                string trailers;
                for (;;) {
                    string t = reader.line(8192);
                    trailers += t + "\r\n";
                    require(trailers.size() <= 65536, "trailers too large");
                    if (t.empty())
                        break;
                }
                parseHeaders(trailers);
                break;
            }
            total += count;
            while (count) {
                size_t n =
                    reader.read(b, (size_t)std::min(count, (unsigned long long)transfer.size()));
                DWORD written = 0;
                require(WriteFile(spool.h, b, (DWORD)n, &written, nullptr) && written == n,
                        "spool write failed");
                count -= n;
            }
            require(reader.line(0).empty(), "bad chunk terminator");
        }
        LARGE_INTEGER z{};
        require(SetFilePointerEx(spool.h, z, nullptr, FILE_BEGIN) != 0, "spool seek failed");
    }
    size_t q = target.find('?');
    string path = target.substr(0, q);
    if (method == "GET" && rewrite(path, loadRules())) {
        ++rewrites;
        diagnostic("applied configured metadata override");
    }
    target = path + (q == string::npos ? "" : target.substr(q));
    Internet req(WinHttpOpenRequest(upstream, wide(method).c_str(), wide(target).c_str(),
                                    L"HTTP/1.1", WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                    (upstreamSecure ? WINHTTP_FLAG_SECURE : 0) |
                                        WINHTTP_FLAG_ESCAPE_DISABLE |
                                        WINHTTP_FLAG_ESCAPE_DISABLE_QUERY));
    require(req.h != nullptr, "cannot create upstream request");
    DWORD disabled =
        WINHTTP_DISABLE_COOKIES | WINHTTP_DISABLE_REDIRECTS | WINHTTP_DISABLE_AUTHENTICATION;
    require(WinHttpSetOption(req.h, WINHTTP_OPTION_DISABLE_FEATURE, &disabled, sizeof(disabled)) !=
                0,
            "cannot disable automatic upstream features");
    DWORD policy = WINHTTP_AUTOLOGON_SECURITY_LEVEL_HIGH;
    require(WinHttpSetOption(req.h, WINHTTP_OPTION_AUTOLOGON_POLICY, &policy, sizeof(policy)) != 0,
            "cannot disable automatic logon");
    string raw;
    for (const auto &h : headers)
        if (!skip.count(lower(h.first)))
            raw += h.first + ": " + h.second + "\r\n";
    wstring wh = wide(raw, 28591);
    ++requests;
    require(WinHttpSendRequest(req.h, wh.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : wh.c_str(),
                               (DWORD)wh.size(), WINHTTP_NO_REQUEST_DATA, 0, (DWORD)total, 0) != 0,
            "upstream send failed");
    unsigned long long remaining = total;
    while (remaining) {
        DWORD n = 0;
        if (spool.h != INVALID_HANDLE_VALUE) {
            require(ReadFile(spool.h, b,
                             (DWORD)std::min(remaining, (unsigned long long)transfer.size()), &n,
                             nullptr) &&
                        n > 0,
                    "spool read failed");
        } else
            n = (DWORD)reader.read(
                b, (size_t)std::min(remaining, (unsigned long long)transfer.size()));
        DWORD sent = 0;
        require(WinHttpWriteData(req.h, b, n, &sent) && sent == n, "upstream upload failed");
        remaining -= n;
    }
    require(WinHttpReceiveResponse(req.h, nullptr) != 0, "upstream response failed");
    DWORD status = 0, sz = sizeof(status);
    require(WinHttpQueryHeaders(req.h, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                                nullptr, &status, &sz, nullptr) != 0,
            "upstream status missing");
    sz = 0;
    WinHttpQueryHeaders(req.h, WINHTTP_QUERY_RAW_HEADERS_CRLF, WINHTTP_HEADER_NAME_BY_INDEX,
                        nullptr, &sz, WINHTTP_NO_HEADER_INDEX);
    require(sz > 0 && sz <= 192 * 1024, "upstream headers oversized");
    std::vector<wchar_t> wb(sz / sizeof(wchar_t) + 1, 0);
    require(WinHttpQueryHeaders(req.h, WINHTTP_QUERY_RAW_HEADERS_CRLF, WINHTTP_HEADER_NAME_BY_INDEX,
                                wb.data(), &sz, WINHTTP_NO_HEADER_INDEX) != 0,
            "upstream headers failed");
    string response = narrow(wb.data(), 28591);
    size_t first = response.find("\r\n");
    require(first != string::npos, "invalid upstream headers");
    Headers rh = parseHeaders(response.substr(first + 2));
    auto drop = hopHeaders(rh);
    if (origin) {
        drop.insert("access-control-allow-origin");
        drop.insert("access-control-allow-credentials");
    }
    string head = "HTTP/1.1 " + std::to_string(status) + " NVIDIA\r\nConnection: close\r\n";
    for (const auto &h : rh)
        if (!drop.count(lower(h.first)))
            head += h.first + ": " + h.second + "\r\n";
    // Close-delimited responses preserve binary/compressed bytes without retaining entire bodies.
    head += cors(origin) + "\r\n";
    started = true;
    sendString(client, head);
    if (method == "HEAD" || status == 204 || status == 304)
        return;
    for (;;) {
        DWORD n = 0;
        require(WinHttpReadData(req.h, b, (DWORD)transfer.size(), &n) != 0, "upstream body failed");
        if (!n)
            break;
        sendBytes(client, b, n);
    }
}
static void serveClient(SOCKET client) {
    bool started = false, origin = false;
    try {
        Reader reader(client);
        string line = reader.line(65536);
        size_t a = line.find(' '), b = line.find(' ', a == string::npos ? a : a + 1);
        require(a != string::npos && b != string::npos && line.substr(b + 1) == "HTTP/1.1",
                "invalid request line");
        string method = line.substr(0, a), target = line.substr(a + 1, b - a - 1);
        require(headerName(method), "invalid method");
        require(!target.empty() && target[0] == '/' && target.find('#') == string::npos,
                "invalid target");
        for (unsigned char c : target)
            require(c >= 33 && c <= 126, "invalid target byte");
        string raw;
        for (;;) {
            string h = reader.line(16384);
            raw += h + "\r\n";
            require(raw.size() <= 96 * 1024, "headers too large");
            if (h.empty())
                break;
        }
        Headers headers = parseHeaders(raw);
        string expectedHost = "127.0.0.1:" + std::to_string(configuredPort);
        string host = getHeader(headers, "host"), o = getHeader(headers, "origin");
        if ((host != "127.0.0.1" && host != "127.0.0.1:80" && host != expectedHost) ||
            (!o.empty() && o != "https://nvfile")) {
            reply(client, 403, "{}");
            return;
        }
        origin = o == "https://nvfile";
        string prefix = "/" + token + "/";
        if (!starts(target, prefix)) {
            reply(client, 404, "{}", origin);
            return;
        }
        target = target.substr(prefix.size() - 1);
        // Validate framing before local controls too: never accept ambiguous Content-Length/TE.
        string cl = getHeader(headers, "content-length"),
               te = getHeader(headers, "transfer-encoding");
        unsigned long long len = 0;
        require(cl.empty() || decimal(cl, len), "invalid length");
        require(cl.empty() || te.empty(), "ambiguous framing");
        if (method == "OPTIONS" && origin &&
            !getHeader(headers, "access-control-request-method").empty()) {
            string m = getHeader(headers, "access-control-request-method");
            if (m != "GET" && m != "HEAD" && m != "POST" && m != "PUT" && m != "PATCH" &&
                m != "DELETE" && m != "OPTIONS") {
                reply(client, 405, "", origin);
                return;
            }
            reply(client, 204, "", true,
                  "Access-Control-Allow-Methods: " + m + "\r\nAccess-Control-Allow-Headers: " +
                      getHeader(headers, "access-control-request-headers") +
                      "\r\nAccess-Control-Allow-Private-Network: true\r\n");
            return;
        }
        if (target == "/health" && method == "GET") {
            reply(client, 200, health(), origin);
            return;
        }
        if (target == "/control/stop") {
            if (method != "POST" || origin || len || !te.empty()) {
                reply(client, 403, "{}");
                return;
            }
            try {
                Lock lock(&maintenance);
                if (!passive)
                    updateEndpoints(false);
                paused = true;
            } catch (...) {
                reply(client, 409, "{\"error\":\"restore failed; kept running\"}");
                return;
            }
            reply(client, 200, "{}");
            SetEvent(stopEvent);
            return;
        }
        if (method == "CONNECT" || method == "TRACE" || !getHeader(headers, "upgrade").empty()) {
            reply(client, 405, "{}", origin);
            return;
        }
        string decoded = unescape(target.substr(0, target.find('?')));
        if (!starts(target, "/nvidia_web_services/") || decoded.find("/../") != string::npos ||
            decoded.find("/./") != string::npos || decoded.find('\\') != string::npos ||
            decoded.find('\0') != string::npos) {
            reply(client, 404, "{}", origin);
            return;
        }
        proxyRequest(client, reader, method, target, headers, origin, started);
    } catch (...) {
        if (!started)
            try {
                reply(client, 502, "{\"error\":\"request or upstream unavailable\"}", origin);
            } catch (...) {
            }
        diagnostic("request failed; no URL, headers or payload logged");
    }
}
static unsigned __stdcall clientThread(void *context) {
    Socket client((SOCKET)(uintptr_t)context);
    serveClient(client.s);
    if (active.fetch_sub(1) == 1)
        SetEvent(drainedEvent);
    return 0;
}
