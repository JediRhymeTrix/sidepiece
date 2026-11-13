#include "../src/core.hpp"
#include <thread>
#include <exception>

static SOCKET testListener(unsigned short &port) {
    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    require(s != INVALID_SOCKET, "test socket failed");
    sockaddr_in a{};
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    a.sin_port = 0;
    require(bind(s, (sockaddr *)&a, sizeof(a)) == 0 && listen(s, 8) == 0, "test bind failed");
    int size = sizeof(a);
    require(getsockname(s, (sockaddr *)&a, &size) == 0, "test port failed");
    port = ntohs(a.sin_port);
    return s;
}
static SOCKET testConnect(unsigned short port) {
    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    sockaddr_in a{};
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    a.sin_port = htons(port);
    require(connect(s, (sockaddr *)&a, sizeof(a)) == 0, "test connect failed");
    DWORD t = 5000;
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (char *)&t, sizeof(t));
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (char *)&t, sizeof(t));
    return s;
}
static string exchange(const string &request) {
    unsigned short port = 0;
    Socket listener(testListener(port));
    std::thread worker([&] {
        Socket c(accept(listener.s, nullptr, nullptr));
        serveClient(c.s);
    });
    string result;
    try {
        Socket client(testConnect(port));
        sendString(client.s, request);
        char b[8192];
        for (;;) {
            int n = recv(client.s, b, sizeof(b), 0);
            require(n >= 0, "test receive failed");
            if (!n)
                break;
            result.append(b, n);
        }
    } catch (...) {
        worker.join();
        throw;
    }
    worker.join();
    return result;
}
int wmain() {
    try {
        WSADATA wd{};
        require(WSAStartup(MAKEWORD(2, 2), &wd) == 0, "test Winsock failed");
        unsigned checks = 0;
        auto check = [&](bool b) {
            require(b, "integration assertion failed");
            ++checks;
        };
        token = "synthetic-test-token";
        passive = true;
        string loopback = std::to_string(127) + ".0.0.1";
        string base = "/" + token;
        auto request = [&](const string &method, const string &path, const string &extra,
                           const string &body) {
            return method + " " + base + path + " HTTP/1.1\r\nHost: " + loopback + "\r\n" + extra +
                   "\r\n" + body;
        };
        string h = exchange(request("GET", "/health", "", {}));
        check(h.find("200 Bridge") != string::npos && h.find("\"native\":true") != string::npos);
        check(exchange("GET /" + token + "/health HTTP/1.1\r\nHost: evil.example\r\n\r\n")
                  .find("403 Bridge") != string::npos);
        check(exchange(request("GET", "/health", "Origin: https://evil.example\r\n", {}))
                  .find("403 Bridge") != string::npos);
        check(exchange("GET /wrong/health HTTP/1.1\r\nHost: " + loopback + "\r\n\r\n")
                  .find("404 Bridge") != string::npos);
        string pre = exchange(
            request("OPTIONS", "/nvidia_web_services/test",
                    "Origin: https://nvfile\r\nAccess-Control-Request-Method: "
                    "POST\r\nAccess-Control-Request-Headers: authorization, content-type\r\n",
                    {}));
        check(pre.find("204 Bridge") != string::npos &&
              pre.find("Access-Control-Allow-Private-Network: true") != string::npos);
        check(exchange(request("POST", "/control/stop", "Origin: https://nvfile\r\n", {}))
                  .find("403 Bridge") != string::npos);
        check(exchange(request("GET", "/nvidia_web_services/%2e%2e/test", "", {}))
                  .find("404 Bridge") != string::npos);
        check(exchange(request("GET", "/health", "Content-Length: 0\r\nContent-Length: 0\r\n", {}))
                  .find("502 Bridge") != string::npos);
        check(exchange(request("GET", "/health",
                               "Content-Length: 0\r\nTransfer-Encoding: chunked\r\n", {}))
                  .find("502 Bridge") != string::npos);
        unsigned short port = 0;
        Socket originListener(testListener(port));
        Internet session(WinHttpOpen(nullptr, WINHTTP_ACCESS_TYPE_NO_PROXY, nullptr, nullptr, 0));
        WinHttpSetTimeouts(session.h, 3000, 3000, 3000, 3000);
        wstring host = wide(loopback);
        Internet conn(WinHttpConnect(session.h, host.c_str(), port, 0));
        check(conn.h != nullptr);
        upstream = conn.h;
        upstreamSecure = false;
        const unsigned char gzip[] = {31,  139, 8, 0, 0,   0,   0,  0,  2, 3, 203, 72, 205,
                                      201, 201, 7, 0, 134, 166, 16, 54, 5, 0, 0,   0};
        string zipped((const char *)gzip, sizeof(gzip));
        for (int iteration = 0; iteration < 4; ++iteration) {
            std::exception_ptr upstreamError;
            std::thread upstreamWorker([&] {
                try {
                    Socket c(accept(originListener.s, nullptr, nullptr));
                    Reader r(c.s);
                    string line = r.line(65536);
                    check(line ==
                          "POST /nvidia_web_services/test/%7b%22x%22:%22a%2fb%22%7d?x=a%2fb&y=2 "
                          "HTTP/1.1");
                    string raw;
                    for (;;) {
                        string l = r.line(8192);
                        raw += l + "\r\n";
                        if (l.empty())
                            break;
                    }
                    Headers hs = parseHeaders(raw);
                    check(getHeader(hs, "authorization") == "Bearer synthetic-test");
                    check(getHeader(hs, "cookie") == "synthetic=value");
                    check(getHeader(hs, "x-test") == "preserved");
                    check(getHeader(hs, "x-hop").empty());
                    check(getHeader(hs, "x-forwarded-for").empty());
                    unsigned long long count = 0;
                    check(decimal(getHeader(hs, "content-length"), count));
                    string body;
                    char b[256];
                    while (count) {
                        size_t n =
                            r.read(b, (size_t)std::min(count, (unsigned long long)sizeof(b)));
                        body.append(b, n);
                        count -= n;
                    }
                    check(body == string("unchanged binary\0body", 21));
                    string response =
                        "HTTP/1.1 " +
                        string(iteration == 2   ? "302 Found"
                               : iteration == 3 ? "401 Unauthorized"
                                                : "418 Teapot") +
                        "\r\nContent-Length: " + std::to_string(zipped.size()) +
                        "\r\nContent-Encoding: gzip\r\nSet-Cookie: synthetic=returned\r\nX-Test: "
                        "upstream\r\nAccess-Control-Allow-Origin: "
                        "https://nvfile\r\nAccess-Control-Allow-Credentials: true\r\nLocation: "
                        "https://evil.example/never-follow\r\nWWW-Authenticate: Basic "
                        "realm=synthetic\r\nConnection: close\r\n\r\n";
                    sendString(c.s, response);
                    sendString(c.s, zipped);
                } catch (...) {
                    upstreamError = std::current_exception();
                }
            });
            string body("unchanged binary\0body", 21), payload = body;
            string headers =
                "Origin: https://nvfile\r\nAuthorization: Bearer synthetic-test\r\nCookie: "
                "synthetic=value\r\nX-Test: preserved\r\nConnection: X-Hop\r\nX-Hop: "
                "remove\r\nX-Forwarded-For: remove\r\n";
            if (iteration == 1) {
                headers += "Transfer-Encoding: chunked\r\n";
                payload = "15\r\n" + body + "\r\n0\r\n\r\n";
            } else
                headers += "Content-Length: " + std::to_string(body.size()) + "\r\n";
            string response = exchange(
                request("POST", "/nvidia_web_services/test/%7b%22x%22:%22a%2fb%22%7d?x=a%2fb&y=2",
                        headers, payload));
            upstreamWorker.join();
            if (upstreamError)
                std::rethrow_exception(upstreamError);
            size_t split = response.find("\r\n\r\n");
            check(split != string::npos);
            check(response.substr(split + 4) == zipped);
            Headers rh = parseHeaders(
                response.substr(response.find("\r\n") + 2, split + 4 - response.find("\r\n") - 2));
            check(getHeader(rh, "access-control-allow-origin") == "https://nvfile");
            check(getHeader(rh, "content-encoding") == "gzip");
            check(getHeader(rh, "set-cookie") == "synthetic=returned");
            check(response.find(iteration == 2   ? "302 NVIDIA"
                                : iteration == 3 ? "401 NVIDIA"
                                                 : "418 NVIDIA") != string::npos);
        }
        std::printf("native integration: %u checks passed (headers, binary/chunked bodies, "
                    "compression, CORS, redirects/auth, access boundaries)\n",
                    checks);
        return 0;
    } catch (const std::exception &e) {
        std::fprintf(stderr, "native integration failed: %s\n", e.what());
        return 1;
    }
}
