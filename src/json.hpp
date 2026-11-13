#pragma once
struct Node {
    size_t a = 0, b = 0;
    char type = 0;
    string text;
    std::map<string, int> obj;
    std::vector<int> arr;
};
// A bounded parser retains byte offsets: configuration and URL edits never reserialize siblings.
struct Json {
    const string &s;
    size_t p = 0;
    std::vector<Node> n;
    explicit Json(const string &x) : s(x) {
        wide(x);
        if (starts(x, "\xef\xbb\xbf"))
            p = 3;
        value(0);
        ws();
        require(p == s.size(), "trailing JSON");
    }
    void ws() {
        while (p < s.size() && (s[p] == ' ' || s[p] == '\t' || s[p] == '\r' || s[p] == '\n'))
            ++p;
    }
    unsigned unit() {
        require(p + 4 <= s.size(), "short unicode escape");
        unsigned u = 0;
        for (int i = 0; i < 4; i++) {
            int h = hex(s[p++]);
            require(h >= 0, "bad unicode escape");
            u = u * 16 + h;
        }
        return u;
    }
    string str() {
        require(p < s.size() && s[p++] == '"', "expected JSON string");
        string out;
        while (p < s.size()) {
            unsigned char c = s[p++];
            if (c == '"')
                return out;
            require(c >= 32, "control in JSON");
            if (c != '\\') {
                out += (char)c;
                continue;
            }
            require(p < s.size(), "short escape");
            c = s[p++];
            switch (c) {
            case '"':
            case '\\':
            case '/':
                out += (char)c;
                break;
            case 'b':
                out += '\b';
                break;
            case 'f':
                out += '\f';
                break;
            case 'n':
                out += '\n';
                break;
            case 'r':
                out += '\r';
                break;
            case 't':
                out += '\t';
                break;
            case 'u': {
                unsigned u = unit();
                wstring w;
                if (u >= 0xd800 && u <= 0xdbff) {
                    require(p + 2 <= s.size() && s[p] == '\\' && s[p + 1] == 'u',
                            "missing surrogate");
                    p += 2;
                    unsigned v = unit();
                    require(v >= 0xdc00 && v <= 0xdfff, "invalid surrogate");
                    w += (wchar_t)u;
                    w += (wchar_t)v;
                } else {
                    require(u < 0xdc00 || u > 0xdfff, "unpaired surrogate");
                    w += (wchar_t)u;
                }
                out += narrow(w);
                break;
            }
            default:
                require(false, "unknown JSON escape");
            }
        }
        throw std::runtime_error("unterminated string");
    }
    int value(int depth) {
        require(depth <= 64 && n.size() < 131072, "JSON complexity limit");
        ws();
        require(p < s.size(), "missing JSON value");
        int k = (int)n.size();
        n.emplace_back();
        n[k].a = p;
        char c = s[p];
        n[k].type = c;
        if (c == '{') {
            ++p;
            ws();
            if (p < s.size() && s[p] == '}')
                ++p;
            else
                for (;;) {
                    ws();
                    string key = str();
                    ws();
                    require(p < s.size() && s[p++] == ':', "missing colon");
                    require(n[k].obj.find(key) == n[k].obj.end(), "duplicate key");
                    int v = value(depth + 1);
                    n[k].obj.emplace(key, v);
                    ws();
                    require(p < s.size(), "unclosed object");
                    char end = s[p++];
                    if (end == '}')
                        break;
                    require(end == ',', "missing comma");
                }
        } else if (c == '[') {
            ++p;
            ws();
            if (p < s.size() && s[p] == ']')
                ++p;
            else
                for (;;) {
                    int v = value(depth + 1);
                    n[k].arr.push_back(v);
                    ws();
                    require(p < s.size(), "unclosed array");
                    char end = s[p++];
                    if (end == ']')
                        break;
                    require(end == ',', "missing comma");
                }
        } else if (c == '"')
            n[k].text = str();
        else if (c == 't' || c == 'f' || c == 'n') {
            string lit = c == 't' ? "true" : c == 'f' ? "false" : "null";
            require(s.compare(p, lit.size(), lit) == 0, "invalid literal");
            p += lit.size();
            n[k].text = lit;
        } else {
            size_t a = p;
            if (s[p] == '-')
                ++p;
            require(p < s.size(), "invalid number");
            if (s[p] == '0')
                ++p;
            else {
                require(s[p] >= '1' && s[p] <= '9', "invalid number");
                while (p < s.size() && s[p] >= '0' && s[p] <= '9')
                    ++p;
            }
            if (p < s.size() && s[p] == '.') {
                ++p;
                size_t q = p;
                while (p < s.size() && s[p] >= '0' && s[p] <= '9')
                    ++p;
                require(p > q, "invalid fraction");
            }
            if (p < s.size() && (s[p] == 'e' || s[p] == 'E')) {
                ++p;
                if (p < s.size() && (s[p] == '+' || s[p] == '-'))
                    ++p;
                size_t q = p;
                while (p < s.size() && s[p] >= '0' && s[p] <= '9')
                    ++p;
                require(p > q, "invalid exponent");
            }
            n[k].type = '0';
            n[k].text = s.substr(a, p - a);
        }
        n[k].b = p;
        return k;
    }
    int member(int k, const string &key) const {
        require(k >= 0 && n[k].type == '{', "expected object");
        auto i = n[k].obj.find(key);
        require(i != n[k].obj.end(), "missing member");
        return i->second;
    }
    string text(int k) const {
        require(n[k].type == '"', "expected string");
        return n[k].text;
    }
};
