#!/usr/bin/env python3
"""Run a command on the analysis server over SSH (paramiko).

Usage:
    python tools/ssh_exec.py "hostname; whoami"
    python tools/ssh_exec.py --sudo "docker ps --format '{{.Names}}'"
    python tools/ssh_exec.py --sudo --docker groot "python -c 'import mujoco;print(mujoco.__version__)'"

On 172.18.101.203 the `luoji` account is in the docker group, so docker runs
without sudo. The `--sudo` flag is only needed on hosts where that group
membership is missing; paramiko cannot answer an interactive sudo prompt, so
the password is fed to `sudo -S` on stdin.
"""

import argparse
import os
import sys

HOST = os.environ.get("GR_HOST", "172.18.101.202")
PORT = int(os.environ.get("GR_PORT", "22"))
USER = os.environ.get("GR_USER", "luoji")
# Never hardcode the credential: this file is committed to the repository.
# Export GR_PASS (or pass --password) in the current shell instead.
PASS = os.environ.get("GR_PASS", "")


def shq(s):
    """POSIX single-quote a string."""
    return "'" + s.replace("'", "'\"'\"'") + "'"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", nargs="?", default="echo ok")
    ap.add_argument("--docker", default=None, help="exec inside this container via docker exec")
    ap.add_argument("--sudo", action="store_true", help="run the remote command as root")
    ap.add_argument("--timeout", type=float, default=3600.0)
    ap.add_argument("--user", default=None, help="override the SSH user")
    ap.add_argument("--password", default=None, help="override the SSH password")
    ap.add_argument("--host", default=None, help="override the SSH host")
    ap.add_argument("--file", default=None,
                    help="local shell script to pipe into bash on the target "
                         "(avoids all PowerShell quoting problems)")
    a = ap.parse_args()

    host = a.host or HOST
    user = a.user or USER
    password = a.password or PASS
    if not password:
        sys.stderr.write("GR_PASS is not set. Export GR_PASS=... (or pass --password ...).\n")
        return 2

    try:
        import paramiko
    except ImportError:
        sys.stderr.write("MISSING paramiko, run: python -m pip install paramiko\n")
        return 127

    cmd = a.command
    script = None
    if a.file:
        with open(a.file, "r", encoding="utf-8") as fh:
            script = fh.read()
        cmd = "bash -s"
        if a.docker:
            cmd = "docker exec -i " + shq(a.docker) + " bash -s"
    elif a.docker:
        cmd = "docker exec " + shq(a.docker) + " bash -lc " + shq(cmd)
    elif a.sudo:
        cmd = "sudo -S -p '' bash -lc " + shq(cmd)

    cli = paramiko.SSHClient()
    cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    cli.connect(
        host,
        port=PORT,
        username=user,
        password=password,
        timeout=25,
        banner_timeout=40,
        auth_timeout=40,
        look_for_keys=False,
        allow_agent=False,
    )
    stdin, stdout, stderr = cli.exec_command(cmd, timeout=a.timeout, get_pty=False)
    if script is not None:
        stdin.write(script)
        stdin.flush()
        try:
            stdin.channel.shutdown_write()
        except Exception:
            pass
    elif a.sudo:
        stdin.write(password + "\n")
        stdin.flush()
        try:
            stdin.channel.shutdown_write()
        except Exception:
            pass

    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    rc = stdout.channel.recv_exit_status()
    cli.close()

    sys.stdout.write(out)
    if err.strip():
        sys.stderr.write("\n-- stderr --\n" + err)
    sys.stdout.write("\n-- exit %d --\n" % rc)
    return rc


if __name__ == "__main__":
    sys.exit(main())