"""Cloud publishing loop: Mac sync → private repo → GitHub Actions runner → results → Mac."""
import json
import subprocess
from datetime import timedelta
from pathlib import Path

import httpx
import pytest

from autopilot import cloud, publisher
from autopilot.cloud_runner import Git, due_posts, run
from autopilot.db import iso, utcnow
from conftest import FakeHost, FakeIG, make_ready


def sh(*a, cwd=None):
    return subprocess.run(a, cwd=cwd, check=True, capture_output=True, text=True).stdout


@pytest.fixture
def cloud_env(env, tmp_path, monkeypatch):
    s, db = env
    for k, v in {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}.items():
        monkeypatch.setenv(k, v)
    remote = tmp_path / "remote.git"
    sh("git", "init", "-q", "--bare", "-b", "main", str(remote))
    sh("git", "clone", "-q", str(remote), str(cloud.repo_dir(s)))
    sh("git", "checkout", "-q", "-B", "main", cwd=cloud.repo_dir(s))
    s.raw["cloud"] = {"enabled": True, "repo": "me/btm-publisher", "branch": "main", "export_days": 10}
    s.raw["general"]["mode"] = "live"
    db.kv_set("activated", True)
    from autopilot.secrets import SecretStore
    sec = SecretStore(s.data_dir)
    sec.set("instagram_access_token", "IGtesttoken1234567890"); sec.set("instagram_user_id", "17841")
    sec.set("instagram_api_host", "https://graph.instagram.com")
    runner_dir = tmp_path / "runner"
    fake = FakeIG()
    client = httpx.Client(transport=httpx.MockTransport(fake.handler))

    def cloud_run():
        if runner_dir.exists():
            sh("git", "pull", "-q", "--rebase", cwd=runner_dir)
        else:
            sh("git", "clone", "-q", str(remote), str(runner_dir))
        return run(runner_dir, client=client, host_factory=FakeHost, git=Git(runner_dir), key=cloud.key(s))
    return s, db, fake, cloud_run, runner_dir


def test_full_loop_publishes_once_and_reports_back(cloud_env):
    s, db, fake, cloud_run, runner_dir = cloud_env
    cid = make_ready(s, db, "image")
    assert cid not in publisher.run_due(s, db)                                              # Mac leaves it to the cloud
    res = cloud.sync(s, db)
    assert res["queued"] == 1 and res["pushed"]
    assert b"IGtesttoken" not in (cloud.repo_dir(s) / "secrets.enc").read_bytes()          # encrypted at rest
    out = cloud_run()
    assert out[cid] == "published" and len(fake.media) == 1
    assert not (runner_dir / "queue" / cid).exists()                                       # media removed after publishing
    assert cloud_run() == {} and len(fake.media) == 1                                      # second trigger: nothing to do
    cloud.sync(s, db)
    row = db.one("SELECT status, platform_post_id FROM content WHERE id=?", (cid,))
    assert row[0] == "published" and row[1] == fake.media[0]["id"]
    cloud.sync(s, db)
    assert not (cloud.repo_dir(s) / "queue" / cid).exists()


def test_crash_after_publish_is_reconciled_not_duplicated(cloud_env):
    s, db, fake, cloud_run, runner_dir = cloud_env
    cid = make_ready(s, db, "image", caption="Cloud crash test caption. Pick the hour, not the week.")
    cloud.sync(s, db)
    fake.fail_next.append(("publish", "timeout_after"))          # Instagram published, but the response was lost
    out = cloud_run()
    assert "retry" in out[cid] and len(fake.media) == 1
    st = json.loads((runner_dir / "state" / f"{cid}.json").read_text())
    st["next_retry_at"] = iso(utcnow() - timedelta(seconds=1))
    (runner_dir / "state" / f"{cid}.json").write_text(json.dumps(st))
    Git(runner_dir).commit_push("time passes")                    # (a real run starts from a fresh checkout)
    out = cloud_run()
    assert out[cid] == "published" and len(fake.media) == 1      # reconciled from Instagram, not posted again
    cloud.sync(s, db)
    assert db.one("SELECT status FROM content WHERE id=?", (cid,))[0] == "published"


def test_pause_reaches_cloud_and_simulation_exports_nothing(cloud_env):
    s, db, fake, cloud_run, runner_dir = cloud_env
    cid = make_ready(s, db, "story")
    db.kv_set("paused", True)
    cloud.sync(s, db)
    assert cloud_run() == {"halted": "paused or not live"} and not fake.media
    db.kv_set("paused", False)
    db.kv_set("activated", False)                                 # not live → withdrawn, never published
    cloud.sync(s, db)
    assert not (cloud.repo_dir(s) / "queue" / cid).exists()
    assert cloud_run() == {"halted": "paused or not live"}


def test_late_posts_skipped_and_story_uses_direct_upload(cloud_env):
    s, db, fake, cloud_run, runner_dir = cloud_env
    late = make_ready(s, db, "image", minutes_ago=400)
    story = make_ready(s, db, "story")
    cloud.sync(s, db)
    out = cloud_run()
    assert out[late] == "skipped" and out[story] == "published" and fake.uploads == 1
    cloud.sync(s, db)
    assert db.one("SELECT status FROM content WHERE id=?", (late,))[0] == "skipped"


def test_check_mode_is_stdlib_only_and_detects_due(cloud_env, tmp_path):
    s, db, fake, cloud_run, runner_dir = cloud_env
    make_ready(s, db, "image")
    cloud.sync(s, db)
    engine = cloud.repo_dir(s) / "engine"
    r = subprocess.run(["python3", "-S", "-c", "import sys; sys.path.insert(0, sys.argv[1]); from autopilot.cloud_runner import main; main(['--root', sys.argv[2], '--check'])",
                        str(engine), str(cloud.repo_dir(s))], capture_output=True, text=True)
    assert r.returncode == 0 and "1 post(s) due" in r.stdout
    wf = (cloud.repo_dir(s) / ".github/workflows/publish.yml").read_text()
    assert "workflow_dispatch" in wf and "CLOUD_KEY" in wf
