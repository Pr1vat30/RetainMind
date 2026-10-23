"""API request and response interceptor for provider gateways."""

from __future__ import annotations

import json
import logging
from typing import Any

import aiohttp

logger = logging.getLogger("pipecat.api.traffic")

_original_request = aiohttp.ClientSession._request
_original_ws_connect = aiohttp.ClientSession._ws_connect


def enable_api_request_logging() -> None:
    """Log outgoing HTTP and WebSocket requests to configured model providers."""
    logger.info("Enabled deep API request and response logging for provider traffic.")

    async def _logged_request(
        self: aiohttp.ClientSession,
        method: str,
        str_or_url: Any,
        *args: Any,
        **kwargs: Any,
    ) -> aiohttp.ClientResponse:
        url_str = str(str_or_url)
        headers = kwargs.get("headers", {})
        data = kwargs.get("data")
        json_data = kwargs.get("json")

        # Format payload preview
        payload_str = ""
        if json_data is not None:
            try:
                payload_str = json.dumps(json_data, indent=2)
            except Exception:
                payload_str = str(json_data)
        elif data is not None:
            if isinstance(data, (bytes, bytearray)):
                payload_str = f"<{len(data)} bytes of binary payload>"
            else:
                payload_str = str(data)

        # Print outgoing request banner
        print("\n" + "═" * 78)
        print("🚀 [OUTGOING API REQUEST TO PROVIDER]")
        print(f"   • Method: {method.upper()}")
        print(f"   • URL:    {url_str}")
        if headers:
            safe_headers = {}
            for k, v in headers.items():
                if "auth" in k.lower() or "key" in k.lower() or "secret" in k.lower():
                    safe_headers[k] = (
                        f"{str(v)[:15]}...{str(v)[-4:]}" if len(str(v)) > 20 else "***"
                    )
                else:
                    safe_headers[k] = str(v)
            print(f"   • Headers: {json.dumps(safe_headers, indent=2)}")
        if payload_str:
            print(f"   • Body / Payload:\n{payload_str}")
        print("═" * 78 + "\n")

        try:
            resp: aiohttp.ClientResponse = await _original_request(
                self, method, str_or_url, *args, **kwargs
            )
            print(
                f"⬅️ [API RESPONSE] {method.upper()} {url_str} ──> Status: {resp.status} {resp.reason}"
            )
            return resp
        except Exception as err:
            print(
                f"❌ [API REQUEST FAILED] {method.upper()} {url_str} ──> Error: {err}"
            )
            raise

    async def _logged_ws_connect(
        self: aiohttp.ClientSession,
        url: Any,
        *args: Any,
        **kwargs: Any,
    ) -> aiohttp.ClientWebSocketResponse:
        url_str = str(url)
        headers = kwargs.get("headers", {})
        print("\n" + "═" * 78)
        print("🔌 [WEBSOCKET CONNECTING TO PROVIDER]")
        print(f"   • URL: {url_str}")
        if headers:
            print(f"   • Headers: {headers}")
        print("═" * 78 + "\n")

        try:
            ws: aiohttp.ClientWebSocketResponse = await _original_ws_connect(
                self, url, *args, **kwargs
            )
            print(f"✅ [WEBSOCKET CONNECTED] {url_str}")
            return ws
        except Exception as err:
            print(f"❌ [WEBSOCKET CONNECTION FAILED] {url_str} ──> Error: {err}")
            raise

    aiohttp.ClientSession._request = _logged_request  # type: ignore
    aiohttp.ClientSession._ws_connect = _logged_ws_connect  # type: ignore

    # Also hook websockets library if imported
    try:
        import websockets.asyncio.client as ws_async_client

        if hasattr(ws_async_client, "connect"):
            _orig_ws_async = ws_async_client.connect

            async def _logged_ws_async_connect(
                uri: Any, *args: Any, **kwargs: Any
            ) -> Any:
                print("\n" + "═" * 78)
                print("🔌 [GOOGLE GEMINI LIVE WEBSOCKET CONNECTING]")
                print(f"   • URI: {uri}")
                print("═" * 78 + "\n")
                return await _orig_ws_async(uri, *args, **kwargs)

            ws_async_client.connect = _logged_ws_async_connect  # type: ignore
    except ImportError:
        pass
