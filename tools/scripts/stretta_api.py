"""Minimal Storefront-API-Client für die Stretta-Recherche.

Bewusst stdlib-only und außerhalb der Rails-App — wie tools/gsc.rb.
Nicht deployen, nicht in den Bundle aufnehmen.
"""

import json
import time
import urllib.request

ENDPOINT = "https://stretta-dev.myshopify.com/api/2025-07/graphql.json"
TOKEN = "d1f7f03ccef19433c2258506ae11b6df"  # öffentlich im Hydrogen-Quelltext
BROWSER_UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/127.0 Safari/537.36"
)


def gql(query, retries=3, timeout=60):
    for attempt in range(retries):
        try:
            request = urllib.request.Request(
                ENDPOINT,
                data=json.dumps({"query": query}).encode(),
                headers={
                    "Content-Type": "application/json",
                    "X-Shopify-Storefront-Access-Token": TOKEN,
                },
            )
            return json.load(urllib.request.urlopen(request, timeout=timeout))
        except Exception:
            if attempt == retries - 1:
                raise
            time.sleep(2 * (attempt + 1))


def fetch(url, timeout=60):
    """HTML abrufen. Ohne Browser-UA antwortet Cloudflare mit 403."""
    request = urllib.request.Request(url, headers={"User-Agent": BROWSER_UA})
    return urllib.request.urlopen(request, timeout=timeout).read().decode("utf-8", "replace")


def metafield_identifiers(pairs):
    return ",".join('{namespace:"%s",key:"%s"}' % (ns, key) for ns, key in pairs)


def paginate(query_template, page_size=250, max_items=None):
    """query_template muss '%(after)s' und '%(first)d' enthalten und
    products{pageInfo{hasNextPage endCursor} nodes{...}} zurückgeben."""
    nodes, cursor = [], None
    while max_items is None or len(nodes) < max_items:
        after = ', after:"%s"' % cursor if cursor else ""
        data = gql(query_template % {"after": after, "first": page_size})
        products = data["data"]["products"]
        nodes += products["nodes"]
        cursor = products["pageInfo"]["endCursor"]
        if not products["pageInfo"]["hasNextPage"]:
            break
    return nodes
