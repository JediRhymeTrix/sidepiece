#pragma once
struct Override {
    string field, from, to;
};
struct EndpointRule {
    string endpoint, method = "GET";
    std::vector<Override> overrides;
};
struct Rules {
    bool enabled = false;
    std::set<string> allow, deny, allowEP, denyEP;
    std::vector<EndpointRule> routes;
};
static bool deviceID(const string &s) {
    if (s.size() < 21 || s.size() > 40)
        return false;
    for (size_t i = 0; i < s.size(); ++i) {
        if (i == 4 || i == 9 || i == 14 || i == 19) {
            if (s[i] != '_')
                return false;
        } else if (i < 19) {
            if (!(s[i] >= '0' && s[i] <= '9') && !(s[i] >= 'A' && s[i] <= 'F'))
                return false;
        } else if (s[i] < '0' || s[i] > '9')
            return false;
    }
    return true;
}
static void knownKeys(const Json &j, int k, const std::set<string> &allowed) {
    require(j.n[k].type == '{', "expected object");
    for (const auto &x : j.n[k].obj)
        require(allowed.count(x.first) != 0, "unknown configuration field");
}
static bool endpointName(const string &s) {
    if (s.empty() || s.size() > 128)
        return false;
    for (char c : s)
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
              c == '_'))
            return false;
    return true;
}
static string scalar(const Json &j, int k) {
    const Node &v = j.n[k];
    require(v.type == '"' || v.type == '0' || v.type == 't' || v.type == 'f' || v.type == 'n',
            "override must be scalar");
    string raw = j.s.substr(v.a, v.b - v.a);
    require(raw.size() <= 1024, "override too large");
    return raw;
}
static Rules parseRules(const string &b) {
    Json j(b);
    Rules r;
    knownKeys(j, 0,
              {"schemaVersion", "enabled", "whitelistDeviceIds", "blacklistDeviceIds",
               "whitelistEndpoints", "blacklistEndpoints", "rules"});
    bool versioned = j.n[0].obj.count("schemaVersion") != 0;
    require(versioned || j.n[0].obj.count("rules") == 0,
            "rules require schemaVersion");
    if (versioned) {
        int v = j.member(0, "schemaVersion");
        require(j.n[v].type == '0' && j.n[v].text == "1", "unsupported schema version");
    }
    for (const auto &kv : j.n[0].obj) {
        const string &key = kv.first;
        const Node &v = j.n[kv.second];
        if (key == "schemaVersion" || key == "rules")
            continue;
        if (key == "enabled") {
            require(v.type == 't' || v.type == 'f', "enabled must be boolean");
            r.enabled = v.type == 't';
            continue;
        }
        std::set<string> *dest = nullptr;
        bool gpu = false;
        if (key == "whitelistDeviceIds") {
            dest = &r.allow;
            gpu = true;
        }
        if (key == "blacklistDeviceIds") {
            dest = &r.deny;
            gpu = true;
        }
        if (key == "whitelistEndpoints")
            dest = &r.allowEP;
        if (key == "blacklistEndpoints")
            dest = &r.denyEP;
        require(dest && v.type == '[' && v.arr.size() <= 64, "invalid rule list");
        for (int a : v.arr) {
            string t = j.text(a);
            require(gpu ? deviceID(t)
                        : (versioned ? endpointName(t) : (t == endpoints[0] || t == endpoints[1])),
                    "invalid rule list value");
            require(dest->insert(t).second, "duplicate rule list value");
        }
    }
    if (versioned) {
        int list = j.member(0, "rules");
        require(j.n[list].type == '[' && j.n[list].arr.size() <= 64, "invalid rules");
        std::set<string> seen;
        for (int k : j.n[list].arr) {
            knownKeys(j, k, {"endpoint", "method", "overrides"});
            EndpointRule route;
            route.endpoint = j.text(j.member(k, "endpoint"));
            route.method = j.text(j.member(k, "method"));
            require(endpointName(route.endpoint), "invalid endpoint name");
            // Only URL-encoded metadata requests may be overridden; bodies remain untouched.
            require(route.method == "GET", "only GET metadata overrides supported");
            require(seen.insert(route.method + "/" + route.endpoint).second,
                    "conflicting endpoint rules");
            int a = j.member(k, "overrides");
            require(j.n[a].type == '[' && !j.n[a].arr.empty() && j.n[a].arr.size() <= 16,
                    "invalid overrides");
            std::set<string> fields;
            for (int o : j.n[a].arr) {
                knownKeys(j, o, {"field", "from", "to"});
                Override v;
                v.field = j.text(j.member(o, "field"));
                require(!v.field.empty() && v.field.size() <= 128 && v.field != "dIDa",
                        "invalid override field");
                require(fields.insert(v.field).second, "conflicting scalar overrides");
                v.from = scalar(j, j.member(o, "from"));
                v.to = scalar(j, j.member(o, "to"));
                route.overrides.push_back(v);
            }
            r.routes.push_back(route);
        }
    } else {
        for (const string &ep : endpoints)
            r.routes.push_back({ep, "GET", {{"iLp", "\"1\"", "\"0\""}, {"iLp", "1", "0"}}});
    }
    return r;
}
static string encodeReplacement(const string &raw) {
    string out;
    for (unsigned char c : raw) {
        out += '%';
        out += "0123456789ABCDEF"[c >> 4];
        out += "0123456789ABCDEF"[c & 15];
    }
    return out;
}
static bool rewrite(string &path, const Rules &r, const string &method = "GET") {
    try {
        if (!r.enabled || path.size() > 65536 || !starts(path, driverPrefix))
            return false;
        size_t slash = path.find('/', driverPrefix.size());
        if (slash == string::npos)
            return false;
        string ep = path.substr(driverPrefix.size(), slash - driverPrefix.size());
        if (!r.allowEP.count(ep) || r.denyEP.count(ep))
            return false;
        const EndpointRule *route = nullptr;
        for (const auto &item : r.routes)
            if (item.endpoint == ep && item.method == method) {
                route = &item;
                break;
            }
        if (!route)
            return false;
        string enc = path.substr(slash + 1), b = unescape(enc);
        Json j(b);
        int ids = j.member(0, "dIDa");
        require(j.n[ids].type == '[' && !j.n[ids].arr.empty() && j.n[ids].arr.size() <= 32,
                "invalid devices");
        for (int a : j.n[ids].arr) {
            string id = upper(j.text(a));
            if (!r.allow.count(id) || r.deny.count(id))
                return false;
        }
        struct Change {
            size_t a, b;
            string text;
        };
        std::vector<Change> changes;
        std::set<string> changedFields;
        std::vector<size_t> offsets;
        for (size_t i = 0; i < enc.size();) {
            offsets.push_back(i);
            i += enc[i] == '%' ? 3 : 1;
        }
        offsets.push_back(enc.size());
        for (const auto &o : route->overrides) {
            auto it = j.n[0].obj.find(o.field);
            if (it == j.n[0].obj.end())
                continue;
            const Node &v = j.n[it->second];
            string raw = b.substr(v.a, v.b - v.a);
            if (raw != o.from || o.from == o.to || changedFields.count(o.field))
                continue;
            size_t a = v.a, z = v.b;
            string replacement = o.to;
            // Preserve existing escapes and every sibling byte when only one byte changes.
            if (raw.size() == replacement.size()) {
                size_t first = raw.size(), last = 0;
                for (size_t i = 0; i < raw.size(); ++i)
                    if (raw[i] != replacement[i]) {
                        first = std::min(first, i);
                        last = i + 1;
                    }
                a += first;
                z = v.a + last;
                replacement = replacement.substr(first, last - first);
                if (z - a == 1 && offsets[z] - offsets[a] == 1)
                    changes.push_back({offsets[a], offsets[z], replacement});
                else
                    changes.push_back({offsets[a], offsets[z], encodeReplacement(replacement)});
            } else
                changes.push_back({offsets[a], offsets[z], encodeReplacement(replacement)});
            changedFields.insert(o.field);
        }
        if (changes.empty())
            return false;
        std::sort(changes.begin(), changes.end(),
                  [](const Change &a, const Change &b) { return a.a > b.a; });
        string out = enc;
        for (const auto &c : changes)
            out.replace(c.a, c.b - c.a, c.text);
        path.replace(slash + 1, string::npos, out);
        return true;
    } catch (...) {
        return false;
    }
}
