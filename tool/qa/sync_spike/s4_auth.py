#!/usr/bin/env python3
"""S4: can a lightweight client (plain HTTP, no AccountSessionStartup) use
each Suwayomi auth mode, including token refresh?

Only for the disposable QA server: it switches auth on with throwaway random
credentials and switches it back to NONE at the end.
"""

import base64
from pathlib import Path
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request

from common import Server, write_json

# aboutServer stays public under every mode, so probe library data.
PROBE = "{ mangas(first: 1) { totalCount } }"
LOGIN = "mutation($u: String!, $p: String!) { login(input: {username: $u, password: $p}) { accessToken refreshToken } }"
REFRESH = "mutation($t: String!) { refreshToken(input: {refreshToken: $t}) { accessToken } }"
SET = "mutation($s: PartialSettingsTypeInput!) { setSettings(input: {settings: $s}) { settings { authMode } } }"


def probe(headers):
    payload = Server(headers=headers).gql(PROBE, raw=True)
    errors = payload.get("errors")
    return "ok" if not errors else errors[0]["message"][:80]


def jwt_exp(token):
    body = token.split(".")[1]
    import json
    return json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def main():
    user, password = "spike", secrets.token_urlsafe(18)
    basic = {"Authorization": "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()}
    results = {}
    open_server = Server()

    # UI_LOGIN with a 20 s access token, so expiry and refresh happen here.
    open_server.gql(SET, {"s": {"authMode": "UI_LOGIN", "authUsername": user, "authPassword": password,
                                "jwtTokenExpiry": "PT20S"}})
    ui = {"anonymous": probe({})}
    tokens = Server().gql(LOGIN, {"u": user, "p": password})["login"]
    bearer = {"Authorization": f"Bearer {tokens['accessToken']}"}
    claims = jwt_exp(tokens["accessToken"])
    ui.update(bearer=probe(bearer), claims={k: claims.get(k) for k in ("aud", "exp", "iat", "sub")},
              refreshClaims={k: v for k, v in jwt_exp(tokens["refreshToken"]).items() if k in ("aud", "exp", "iat")},
              wrongPassword=Server().gql(LOGIN, {"u": user, "p": "wrong"}, raw=True).get("errors", [{}])[0]
              .get("message", "accepted")[:80])
    time.sleep(25)
    ui["bearerAfterExpiry"] = probe(bearer)
    first = Server().gql(REFRESH, {"t": tokens["refreshToken"]})["refreshToken"]["accessToken"]
    second = Server().gql(REFRESH, {"t": tokens["refreshToken"]}, raw=True)
    ui["refreshed"] = probe({"Authorization": f"Bearer {first}"})
    ui["refreshTokenReusable"] = "errors" not in second
    ui["refreshAsAccess"] = probe({"Authorization": f"Bearer {tokens['refreshToken']}"})
    ui["basicWhileUiLogin"] = probe(basic)
    results["UI_LOGIN"] = ui
    authed = Server(headers={"Authorization": f"Bearer {first}"})

    authed.gql(SET, {"s": {"authMode": "BASIC_AUTH", "jwtTokenExpiry": "PT5M"}})
    results["BASIC_AUTH"] = {"anonymous": probe({}), "basic": probe(basic),
                             "wrong": probe({"Authorization": "Basic " + base64.b64encode(b"spike:no").decode()})}

    Server(headers=basic).gql(SET, {"s": {"authMode": "SIMPLE_LOGIN"}})
    simple = {"anonymous": probe({})}
    opener = urllib.request.build_opener(NoRedirect)
    form = urllib.parse.urlencode({"user": user, "pass": password}).encode()
    try:
        opener.open(urllib.request.Request(f"{open_server.base}/login.html", data=form), timeout=30)
        cookie = None
    except urllib.error.HTTPError as error:
        cookie = (error.headers.get("Set-Cookie") or "").split(";")[0] or None
        simple["loginStatus"] = error.code
    simple["cookie"] = probe({"Cookie": cookie}) if cookie else "no cookie"
    results["SIMPLE_LOGIN"] = simple

    Server(headers={"Cookie": cookie} if cookie else basic).gql(SET, {"s": {"authMode": "NONE"}})
    results["restoredAnonymous"] = probe({})
    for mode, values in results.items():
        print(mode, values)
    write_json(Path(__file__).parent / "results" / "s4-auth.json", results)


if __name__ == "__main__":
    main()
