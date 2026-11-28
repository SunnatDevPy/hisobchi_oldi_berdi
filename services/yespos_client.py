"""Phase 2 YesPOS Marketplace & 1C Integration API client + cached product catalog service."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import httpx

from config import BASE_DIR, get_settings
from database.crud import _cyr_to_lat, now_local

logger = logging.getLogger("yespos_client")


class YesPOSClient:
    """
    Async client for YesPOS Marketplace API and (when enabled) 1C Integration API.

    Respects documented rate limits:
    - /marketplace/products: 15 req/min (1 min server cache)
    - /marketplace/products/info: 10 req/min
    """

    def __init__(
        self,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None,
        branch_id: Optional[str] = None,
        one_c_base_url: Optional[str] = None,
        one_c_api_key: Optional[str] = None,
        min_interval_sec: float = 6.2,
    ) -> None:
        settings = get_settings()
        self.base_url = (base_url or settings.YESPOS_BASE_URL).rstrip("/")
        self.api_key = api_key if api_key is not None else settings.YESPOS_API_KEY
        self.branch_id = branch_id if branch_id is not None else settings.YESPOS_BRANCH_ID
        self.one_c_base_url = (one_c_base_url or settings.YESPOS_1C_BASE_URL).rstrip("/")
        self.one_c_api_key = one_c_api_key or settings.YESPOS_1C_API_KEY
        self._last_request_ts = 0.0
        self._min_interval_sec = min_interval_sec

    async def _throttle(self) -> None:
        if self._min_interval_sec <= 0:
            return
        elapsed = time.monotonic() - self._last_request_ts
        if self._last_request_ts > 0 and elapsed < self._min_interval_sec:
            await asyncio.sleep(self._min_interval_sec - elapsed)
        self._last_request_ts = time.monotonic()

    async def get_marketplace_products(self, product_ids: Optional[List[int]] = None) -> Dict[str, Any]:
        """Fetch product categories and items from /api/v1/marketplace/products."""
        await self._throttle()
        payload = {"product_ids": product_ids} if product_ids else {}
        headers = {"API-Key": self.api_key, "Content-Type": "application/json"}
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{self.base_url}/api/v1/marketplace/products",
                headers=headers,
                json=payload,
            )
            resp.raise_for_status()
            return resp.json()

    async def get_products_info(
        self, page: int = 1, limit: int = 500, product_ids: Optional[List[int]] = None
    ) -> Dict[str, Any]:
        """Fetch stock and selling price from /api/v1/marketplace/products/info."""
        await self._throttle()
        payload = {"product_ids": product_ids} if product_ids else {}
        headers = {
            "API-Key": self.api_key,
            "Branch": str(self.branch_id),
            "Content-Type": "application/json",
        }
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{self.base_url}/api/v1/marketplace/products/info",
                params={"page": page, "limit": limit},
                headers=headers,
                json=payload,
            )
            resp.raise_for_status()
            return resp.json()

    async def get_receipts_1c(self, from_ms: int, to_ms: int) -> Dict[str, Any]:
        """Phase 2: Fetch sales receipts with cost & price from /api/v1/1c/receipts1C."""
        if not self.one_c_base_url or not self.one_c_api_key:
            raise RuntimeError("YesPOS 1C API hali sozlanmagan (YESPOS_1C_BASE_URL / YESPOS_1C_API_KEY).")
        headers = {"X-API-Key": self.one_c_api_key}
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(
                f"{self.one_c_base_url}/api/v1/1c/receipts1C",
                params={"fromDate": from_ms, "toDate": to_ms},
                headers=headers,
            )
            resp.raise_for_status()
            return resp.json()

    async def get_purchase_orders_1c(self, from_ms: int, to_ms: int) -> Dict[str, Any]:
        """Phase 2: Fetch incoming purchase orders from /api/v1/1c/purchOrders1C."""
        if not self.one_c_base_url or not self.one_c_api_key:
            raise RuntimeError("YesPOS 1C API hali sozlanmagan (YESPOS_1C_BASE_URL / YESPOS_1C_API_KEY).")
        headers = {"X-API-Key": self.one_c_api_key}
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(
                f"{self.one_c_base_url}/api/v1/1c/purchOrders1C",
                params={"fromDate": from_ms, "toDate": to_ms},
                headers=headers,
            )
            resp.raise_for_status()
            return resp.json()


def _extract_barcode(raw: Dict[str, Any]) -> str:
    """Extract barcode(s) cleanly from any known YesPOS product field."""
    candidates: List[str] = []
    for key in ("barcode", "barcodes", "ean", "ean13", "gtin", "code"):
        val = raw.get(key)
        if isinstance(val, list):
            for item in val:
                s = str(item or "").strip()
                if s and s not in candidates:
                    candidates.append(s)
        elif val is not None:
            s = str(val).strip()
            if s and s not in candidates:
                candidates.append(s)
    return ", ".join(candidates)


def _normalize_image_url(raw_img: str, base_url: str) -> str:
    img = (raw_img or "").strip()
    if not img:
        return ""
    if img.startswith("http://") or img.startswith("https://"):
        return img
    return f"{base_url.rstrip('/')}/{img.lstrip('/')}"


class YesPOSCatalogService:
    """Rate-limit safe, disk-backed YesPOS product catalog with instant multi-field search."""

    def __init__(
        self,
        cache_path: Optional[Path] = None,
        ttl_seconds: int = 600,
        client_factory=None,
    ) -> None:
        self.cache_path = cache_path or (BASE_DIR / "data" / "yespos_catalog_cache.json")
        self.ttl_seconds = ttl_seconds
        self._client_factory = client_factory or YesPOSClient
        self._lock = asyncio.Lock()
        self._categories: List[Dict[str, Any]] = []
        self._products: List[Dict[str, Any]] = []
        self._synced_at: str = ""
        self._synced_mono: float = 0.0
        self._prices_ready: bool = False
        self._syncing_prices: bool = False
        self._last_error: str = ""
        self._price_task: Optional[asyncio.Task] = None
        self._disk_loaded: bool = False

    def is_configured(self) -> bool:
        settings = get_settings()
        return bool((settings.YESPOS_API_KEY or "").strip())

    def _load_from_disk_if_needed(self) -> None:
        if self._disk_loaded:
            return
        self._disk_loaded = True
        if not self.cache_path.is_file():
            return
        try:
            raw = json.loads(self.cache_path.read_text(encoding="utf-8"))
            if isinstance(raw, dict) and isinstance(raw.get("products"), list):
                self._categories = list(raw.get("categories") or [])
                self._products = list(raw.get("products") or [])
                self._synced_at = str(raw.get("synced_at") or "")
                self._prices_ready = bool(raw.get("prices_ready", False))
                self._synced_mono = 0.0  # trigger stale background refresh if needed
        except Exception as exc:
            logger.warning("Failed to load YesPOS disk cache: %s", exc)

    def _save_to_disk(self) -> None:
        try:
            self.cache_path.parent.mkdir(parents=True, exist_ok=True)
            payload = {
                "synced_at": self._synced_at,
                "prices_ready": self._prices_ready,
                "categories": self._categories,
                "products": self._products,
            }
            tmp = self.cache_path.with_suffix(".tmp")
            tmp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            tmp.replace(self.cache_path)
        except Exception as exc:
            logger.warning("Failed to persist YesPOS disk cache: %s", exc)

    def _build_search_blob(self, item: Dict[str, Any]) -> None:
        name = str(item.get("name") or "")
        cat = str(item.get("category_name") or "")
        desc = str(item.get("description") or "")
        sku = str(item.get("sku") or "")
        barcode = str(item.get("barcode") or "")
        classcode = str(item.get("classcode") or "")
        pkg = str(item.get("package_code") or "")
        pid = str(item.get("id") or "")
        raw_blob = f"{name} {sku} {barcode} {classcode} {pkg} {cat} {desc} {pid}".lower()
        lat_blob = f"{_cyr_to_lat(name)} {_cyr_to_lat(cat)} {_cyr_to_lat(desc)}".lower()
        item["_search"] = f"{raw_blob} {lat_blob}"

    def _parse_products_response(self, resp: Dict[str, Any], base_url: str) -> None:
        prev_info: Dict[int, Dict[str, Any]] = {
            int(p["id"]): {
                "price": p.get("price"),
                "stock": p.get("stock"),
                "low_stock": p.get("low_stock"),
            }
            for p in self._products
            if p.get("id") is not None
        }
        raw_cats = resp.get("data") or []
        categories: List[Dict[str, Any]] = []
        products: List[Dict[str, Any]] = []
        seen_ids: set[int] = set()

        for cat in raw_cats:
            if not isinstance(cat, dict):
                continue
            cid = int(cat.get("id") or 0)
            cname = str(cat.get("name") or "Kategoriyasiz").strip() or "Kategoriyasiz"
            parent_id = int(cat.get("parent") or 0)
            cat_prods = cat.get("products") or []
            valid_count = 0

            for p in cat_prods:
                if not isinstance(p, dict):
                    continue
                pid = int(p.get("id") or 0)
                if pid <= 0 or pid in seen_ids:
                    continue
                seen_ids.add(pid)
                valid_count += 1
                prev = prev_info.get(pid, {})
                sku = str(p.get("sku") or p.get("article") or "").strip()
                barcode = _extract_barcode(p)
                item: Dict[str, Any] = {
                    "id": pid,
                    "name": str(p.get("name") or "").strip(),
                    "sku": sku,
                    "barcode": barcode,
                    "classcode": str(p.get("classcode") or "").strip(),
                    "package_code": str(p.get("package_code") or "").strip(),
                    "category_id": cid,
                    "category_name": cname,
                    "description": str(p.get("description") or "").strip(),
                    "image_url": _normalize_image_url(str(p.get("image") or ""), base_url),
                    "price": prev.get("price"),
                    "stock": prev.get("stock"),
                    "low_stock": prev.get("low_stock"),
                }
                self._build_search_blob(item)
                products.append(item)

            categories.append(
                {
                    "id": cid,
                    "parent": parent_id,
                    "name": cname,
                    "product_count": valid_count,
                }
            )

        categories.sort(key=lambda c: (-int(c["product_count"]), str(c["name"]).lower()))
        self._categories = categories
        self._products = products
        self._synced_at = now_local().strftime("%Y-%m-%d %H:%M")
        self._synced_mono = time.monotonic()

    async def _sync_all_prices(self, client: YesPOSClient) -> None:
        self._syncing_prices = True
        try:
            price_map: Dict[int, Dict[str, Any]] = {}
            page = 1
            total_pages = 1
            while page <= total_pages and page <= 25:
                res = await client.get_products_info(page=page, limit=500)
                rows = res.get("data") or []
                for r in rows:
                    if not isinstance(r, dict):
                        continue
                    pid = int(r.get("product_id") or r.get("id") or 0)
                    if pid > 0:
                        price_map[pid] = {
                            "price": float(r.get("price") or 0.0),
                            "stock": float(r.get("stock") or 0.0),
                            "low_stock": float(r.get("low_stock") or 0.0),
                        }
                pag = res.get("pagination") or {}
                total_pages = int(pag.get("total_pages") or 1)
                if not rows:
                    break
                page += 1

            for p in self._products:
                info = price_map.get(int(p["id"]))
                if info is not None:
                    p["price"] = info["price"]
                    p["stock"] = info["stock"]
                    p["low_stock"] = info["low_stock"]
            self._prices_ready = True
            self._synced_at = now_local().strftime("%Y-%m-%d %H:%M")
            self._synced_mono = time.monotonic()
            self._last_error = ""
            self._save_to_disk()
        except Exception as exc:
            self._last_error = str(exc)
            logger.warning("YesPOS prices sync error: %s", exc)
        finally:
            self._syncing_prices = False

    async def ensure_loaded(
        self,
        *,
        force: bool = False,
        wait_for_prices: bool = False,
    ) -> None:
        """Ensure catalog is loaded in memory; refresh prices safely in background or inline."""
        self._load_from_disk_if_needed()
        if not self.is_configured():
            return

        now_m = time.monotonic()
        is_stale = (not self._products) or (self._synced_mono <= 0) or ((now_m - self._synced_mono) > self.ttl_seconds)
        if not force and not is_stale and (self._prices_ready or not wait_for_prices):
            return

        async with self._lock:
            now_m = time.monotonic()
            is_stale = (not self._products) or (self._synced_mono <= 0) or ((now_m - self._synced_mono) > self.ttl_seconds)
            if not force and not is_stale and (self._prices_ready or not wait_for_prices):
                return
            client = self._client_factory()
            try:
                if force or not self._products or is_stale:
                    resp = await client.get_marketplace_products()
                    self._parse_products_response(resp, client.base_url)
                    self._last_error = ""
                    self._save_to_disk()
            except Exception as exc:
                self._last_error = str(exc)
                logger.warning("YesPOS products fetch error: %s", exc)
                if not self._products:
                    raise

            if wait_for_prices:
                if self._price_task and not self._price_task.done():
                    await self._price_task
                else:
                    await self._sync_all_prices(client)
            elif not self._syncing_prices and (force or not self._prices_ready or is_stale):
                self._price_task = asyncio.create_task(self._sync_all_prices(client))

    def query_products(
        self,
        *,
        q: str = "",
        category_id: Optional[int] = None,
        stock_filter: str = "all",
        sort: str = "name_asc",
        page: int = 1,
        limit: int = 60,
    ) -> Dict[str, Any]:
        """Search and paginate cached YesPOS products across name, SKU, barcode, MXIK, category."""
        self._load_from_disk_if_needed()
        for p in self._products:
            if "_search" not in p:
                self._build_search_blob(p)

        # Build descendant category ID set if a parent category is selected
        allowed_cat_ids: Optional[set[int]] = None
        if category_id is not None:
            allowed_cat_ids = {int(category_id)}
            changed = True
            while changed:
                changed = False
                for c in self._categories:
                    cid = int(c["id"])
                    if int(c.get("parent") or 0) in allowed_cat_ids and cid not in allowed_cat_ids:
                        allowed_cat_ids.add(cid)
                        changed = True

        clean_q = " ".join((q or "").strip().lower().split())
        tokens = clean_q.split() if clean_q else []
        lat_tokens = [_cyr_to_lat(t) for t in tokens]

        in_stock_total = 0
        out_of_stock_total = 0
        for p in self._products:
            st = p.get("stock")
            if st is not None:
                if float(st) > 0:
                    in_stock_total += 1
                else:
                    out_of_stock_total += 1

        matched: List[tuple[int, Dict[str, Any]]] = []
        for p in self._products:
            if allowed_cat_ids is not None and int(p.get("category_id") or 0) not in allowed_cat_ids:
                continue

            st = p.get("stock")
            low_st = p.get("low_stock")
            if stock_filter == "in_stock":
                if st is None or float(st) <= 0:
                    continue
            elif stock_filter == "out_of_stock":
                if st is None or float(st) > 0:
                    continue
            elif stock_filter == "low_stock":
                if st is None or float(st) <= 0:
                    continue
                thresh = float(low_st) if (low_st is not None and float(low_st) > 0) else 5.0
                if float(st) > thresh:
                    continue

            rank = 2
            if tokens:
                blob = p.get("_search") or ""
                ok = True
                for raw_t, lat_t in zip(tokens, lat_tokens):
                    if raw_t not in blob and (not lat_t or lat_t not in blob):
                        ok = False
                        break
                if not ok:
                    continue
                # Prioritize exact SKU / barcode / ID / name prefix matches
                sku_low = str(p.get("sku") or "").lower()
                bc_low = str(p.get("barcode") or "").lower()
                name_low = str(p.get("name") or "").lower()
                if clean_q == sku_low or (bc_low and clean_q in bc_low) or clean_q == str(p.get("id")):
                    rank = 0
                elif name_low.startswith(clean_q) or sku_low.startswith(clean_q):
                    rank = 1

            matched.append((rank, p))

        if sort == "price_desc":
            matched.sort(key=lambda x: (x[0], -(float(x[1].get("price") or 0.0)), str(x[1].get("name") or "").lower()))
        elif sort == "price_asc":
            matched.sort(key=lambda x: (x[0], float(x[1].get("price") or 0.0), str(x[1].get("name") or "").lower()))
        elif sort == "stock_desc":
            matched.sort(key=lambda x: (x[0], -(float(x[1].get("stock") or -1.0)), str(x[1].get("name") or "").lower()))
        elif sort == "stock_asc":
            matched.sort(key=lambda x: (x[0], float(x[1].get("stock") if x[1].get("stock") is not None else 1e12), str(x[1].get("name") or "").lower()))
        else:
            matched.sort(key=lambda x: (x[0], str(x[1].get("name") or "").lower()))

        total_matched = len(matched)
        safe_limit = max(1, min(limit, 200))
        total_pages = max(1, (total_matched + safe_limit - 1) // safe_limit)
        safe_page = max(1, min(page, total_pages))
        start = (safe_page - 1) * safe_limit
        slice_items = matched[start : start + safe_limit]

        public_items = [
            {k: v for k, v in item.items() if not k.startswith("_")}
            for _, item in slice_items
        ]
        return {
            "configured": self.is_configured(),
            "synced_at": self._synced_at,
            "prices_ready": self._prices_ready,
            "syncing": self._syncing_prices,
            "last_error": self._last_error,
            "total_catalog_products": len(self._products),
            "total_categories": len(self._categories),
            "in_stock_count": in_stock_total,
            "out_of_stock_count": out_of_stock_total,
            "matched_count": total_matched,
            "page": safe_page,
            "limit": safe_limit,
            "total_pages": total_pages,
            "has_more": safe_page < total_pages,
            "categories": self._categories,
            "items": public_items,
        }


_yespos_catalog_singleton: Optional[YesPOSCatalogService] = None


def get_yespos_catalog_service() -> YesPOSCatalogService:
    global _yespos_catalog_singleton
    if _yespos_catalog_singleton is None:
        _yespos_catalog_singleton = YesPOSCatalogService()
    return _yespos_catalog_singleton
