"""Phase 2 YesPOS Marketplace & 1C Integration API client (rate-limit safe)."""

from __future__ import annotations

import asyncio
import time
from typing import Any, Dict, List, Optional

import httpx

from config import get_settings


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
    ) -> None:
        settings = get_settings()
        self.base_url = (base_url or settings.YESPOS_BASE_URL).rstrip("/")
        self.api_key = api_key or settings.YESPOS_API_KEY
        self.branch_id = branch_id or settings.YESPOS_BRANCH_ID
        self.one_c_base_url = (one_c_base_url or settings.YESPOS_1C_BASE_URL).rstrip("/")
        self.one_c_api_key = one_c_api_key or settings.YESPOS_1C_API_KEY
        self._last_request_ts = 0.0
        self._min_interval_sec = 6.5  # Safe under 10 req/min limit

    async def _throttle(self) -> None:
        elapsed = time.monotonic() - self._last_request_ts
        if elapsed < self._min_interval_sec:
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
