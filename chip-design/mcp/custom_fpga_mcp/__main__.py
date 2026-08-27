"""Allow `python -m custom_fpga_mcp <subcommand>`.

With no arguments this starts the MCP server on stdio, which is how the IDE
launches it. Everything else goes through the CLI parser.
"""

from __future__ import annotations

import sys

from .cli import main

if __name__ == "__main__":
    argv = sys.argv[1:] or ["serve"]
    raise SystemExit(main(argv))
