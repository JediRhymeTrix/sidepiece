#include "../src/core.hpp"
static string encode(const string &s) {
    string o;
    for (unsigned char c : s) {
        o += '%';
        o += "0123456789ABCDEF"[c >> 4];
        o += "0123456789ABCDEF"[c & 15];
    }
    return o;
}
int wmain() {
    Rules r =
        parseRules("{\"enabled\":true,\"whitelistDeviceIds\":[\"ABCD_10DE_1234_5678_1\"],"
                   "\"blacklistDeviceIds\":[\"DCBA_10DE_8765_4321_1\"],\"whitelistEndpoints\":["
                   "\"getDispDrvrByDevid\",\"getDispDrvrDtlsByDevid\"],\"blacklistEndpoints\":[]}");
    unsigned checks = 0;
    auto check = [&](bool ok) {
        require(ok, "native self-test failed");
        ++checks;
    };
    std::vector<std::pair<string, bool>> cases = {
        {R"({"dIDa":["ABCD_10DE_1234_5678_1"],"iLp":"1","osC":"10.0","osB":"26340"})", true},
        {R"({"dIDa":["abcd_10de_1234_5678_1"],"iLp":"1"})", true},
        {R"({ "extra":{"iLp":1},"dIDa":["ABCD_10DE_1234_5678_1"],"iLp":1 })", true},
        {R"({"dIDa":["DCBA_10DE_8765_4321_1"],"iLp":"1"})", false},
        {R"({"dIDa":["dcba_10de_8765_4321_1"],"iLp":"1"})", false},
        {R"({"dIDa":["ABCD_10DE_1234_5678_1","DCBA_10DE_8765_4321_1"],"iLp":"1"})", false},
        {R"({"dIDa":["0000_10DE_0000_0000_1"],"iLp":1})", false},
        {R"({"dIDa":[],"iLp":1})", false},
        {R"({"dIDa":["ABCD_10DE_1234_5678_1"]})", false},
        {R"({"dIDa":["ABCD_10DE_1234_5678_1"],"iLp":"0"})", false},
        {R"({"dIDa":["ABCD_10DE_1234_5678_1"],"iLp":1,"iLp":1})", false},
        {R"({"dIDa":["ABCD_10DE_1234_5678_1"],"iLp":1,"\u0069Lp":1})", false},
        {R"({"dIDa":["ABCD_10DE_1234_5678_1"],"iLp":)", false},
        {R"({"dIDa":"ABCD_10DE_1234_5678_1","iLp":1})", false},
        {R"({"dIDa":["ABCD_10DE_1234_5678_1"],"iLp":1.0})", false},
        {R"({"dIDa":["ABCD_10DE_1234_5678_1"],"iLp":"\u0031"})", false}};
    for (const string &ep : endpoints)
        for (const auto &c : cases) {
            string p = driverPrefix + ep + "/" + encode(c.first), before = p;
            check(rewrite(p, r) == c.second);
            if (c.second) {
                Json j(c.first);
                size_t pos = j.n[j.member(0, "iLp")].a;
                if (c.first[pos] == '"')
                    ++pos;
                string expected = c.first;
                expected[pos] = '0';
                check(p == driverPrefix + ep + "/" + encode(expected));
            } else
                check(p == before);
        }
    string p = driverPrefix + endpoints[0] + "/" + encode(cases[0].first);
    for (int i = 0; i < 5; ++i) {
        Rules veto = r;
        if (i == 0)
            veto.enabled = false;
        if (i == 1)
            veto.allow.clear();
        if (i == 2)
            veto.deny.insert(*r.allow.begin());
        if (i == 3)
            veto.allowEP.clear();
        if (i == 4)
            veto.denyEP.insert(endpoints[0]);
        string copy = p;
        check(!rewrite(copy, veto) && copy == p);
    }
    for (string invalid : {R"({"enabled":true,"unknown":1})", R"({"enabled":true,"enabled":false})",
                           R"({"enabled":"true"})", R"({"whitelistDeviceIds":["bad"]})",
                           R"({"whitelistEndpoints":["account"]})"}) {
        bool rejected = false;
        try {
            parseRules(invalid);
        } catch (...) {
            rejected = true;
        }
        check(rejected);
    }
    string loc =
        R"({ "localizedConfig":{"gfwsl":{"server":"https://gfwsl.geforce.com/"},"other":"newer"},"configTimestamp":"preserve","etag":"keep" })";
    string prof =
        R"([{"componentName":"grd","updateCheckerProfiles":[{"otaBaseUrl":"https://gfwsl.geforce.com/","apiPart":"keep"}],"downloaderProfiles":[{"trustedSigners":["NVIDIA"]}]},{"componentName":"crd","updateCheckerProfiles":[{"otaBaseUrl":"https://gfwsl.geforce.com/"}]},{"componentName":"nvapp","updateCheckerProfiles":[{"otaBaseUrl":"https://ota.nvidia.com"}]}])";
    for (const auto &pair : std::vector<std::pair<string, bool>>{{loc, true}, {prof, false}}) {
        string local = "http://127.0.0.1/test/";
        string edited = editEndpoints(pair.first, pair.second, official, local);
        check(edited != pair.first);
        check(editEndpoints(edited, pair.second, local, official) == pair.first);
        check(editEndpoints(edited, pair.second, official, local) == edited);
    }
    bool duplicate = false;
    try {
        getHeader(parseHeaders("Host: a\r\nHost: b\r\n\r\n"), "host");
    } catch (...) {
        duplicate = true;
    }
    check(duplicate);
    check(hopHeaders(parseHeaders("Connection: X-Test, close\r\n\r\n")).count("x-test") == 1);
    std::printf("native self-test: %u checks passed\n", checks);
    return 0;
}
