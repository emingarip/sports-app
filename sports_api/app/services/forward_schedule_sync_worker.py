from __future__ import annotations

import argparse
import asyncio
import os
from datetime import date

from app.services.forward_schedule_sync import (
    ForwardScheduleSyncManager,
    ForwardScheduleSyncStatusStore,
)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run forward/backward schedule sync in a detached worker.")
    parser.add_argument("--provider-slug", required=True)
    parser.add_argument("--start-date", required=True)
    parser.add_argument("--direction", default="forward")
    parser.add_argument("--max-days", type=int, default=365)
    return parser


async def _main() -> None:
    args = _build_parser().parse_args()
    store = ForwardScheduleSyncStatusStore.default()
    store.ensure_dir()
    store.clear_stop_request()
    store.write_pid(os.getpid())
    manager = ForwardScheduleSyncManager(
        execution_mode="task",
        status_store=store,
    )
    try:
        await manager.run_foreground(
            provider_slug=args.provider_slug,
            start_date=date.fromisoformat(args.start_date),
            direction=args.direction,
            max_days=args.max_days,
            pid=os.getpid(),
        )
    finally:
        store.remove_pid()
        store.clear_stop_request()


if __name__ == "__main__":
    asyncio.run(_main())
