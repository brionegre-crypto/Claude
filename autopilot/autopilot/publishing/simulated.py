"""Simulation publisher used until activation: records exactly what WOULD be published, touches no real account."""
from __future__ import annotations

import json
import shutil
import uuid

from autopilot.db import iso
from autopilot.publishing.base import Capability, PublishResult, Publisher


class SimulatedPublisher(Publisher):
    name = "simulated"

    def __init__(self, s, platform: str, real: Publisher | None = None):
        self.s, self.platform, self.real = s, platform, real
        self.out = s.data_dir / "simulated-outbox"
        self.out.mkdir(exist_ok=True)

    def capabilities(self):
        return self.real.capabilities() if self.real else [Capability(self.platform, "*", True, "simulated", "")]

    def autonomous(self, fmt):
        return self.real.autonomous(fmt) if self.real else True

    def publish(self, content, assets, on_container):
        pid = "sim_" + uuid.uuid4().hex[:12]
        on_container("simc_" + pid)
        d = self.out / f"{content['scheduled_at'][:16].replace(':', '')}_{content['platform']}_{content['format']}_{content['id'][:8]}"
        d.mkdir(exist_ok=True)
        (d / "post.json").write_text(json.dumps({"would_publish_at": iso(), "caption": content.get("caption_full"),
                                                  "format": content["format"], "platform": content["platform"],
                                                  "assets": [a["path"] for a in assets]}, indent=2))
        for a in assets:
            shutil.copy(a["path"], d)
        return PublishResult(post_id=pid, permalink=None, raw={"simulated": True, "outbox": str(d)})

    def reconcile(self, content, container_id):
        return None
