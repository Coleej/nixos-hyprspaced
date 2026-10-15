{config, ...}: {
  # Runs qmd's own MCP server as a long-lived HTTP daemon (instead of
  # stdio-per-launch) so the embedding/reranking models stay warm across
  # Claude Code sessions. Point Claude Code's mcpServers config at
  # http://localhost:8181/mcp.
  #
  # Imported only on hosts with real GPU access — every desktop host, via
  # modules/home/default.nix (x1, thinkpad, amd-workstation).
  # wsl is excluded: WSL2 has no real GPU passthrough (node-llama-cpp falls
  # back to slow CPU inference there), so that Claude Code instance instead
  # points at a GPU-accelerated qmd server running natively on the Windows
  # host it runs under (~3x faster on the same RX 6700 XT via native Vulkan,
  # vs. WSL's fake/absent DRM device). See project notes for that setup.
  systemd.user.services.qmd-mcp = {
    Unit.Description = "qmd MCP HTTP server";
    Service = {
      ExecStart = "${config.programs.qmd.package}/bin/qmd mcp --http";
      Restart = "on-failure";
    };
    Install.WantedBy = ["default.target"];
  };
}
