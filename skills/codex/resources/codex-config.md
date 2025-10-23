Config reference
Key	Type / Values	Notes
model	string	Model to use (e.g., gpt-5-codex).
model_provider	string	Provider id from model_providers (default: openai).
model_context_window	number	Context window tokens.
model_max_output_tokens	number	Max output tokens.
approval_policy	untrusted | on-failure | on-request | never	When to prompt for approval.
sandbox_mode	read-only | workspace-write | danger-full-access	OS sandbox policy.
sandbox_workspace_write.writable_roots	array	Extra writable roots in workspace‑write.
sandbox_workspace_write.network_access	boolean	Allow network in workspace‑write (default: false).
sandbox_workspace_write.exclude_tmpdir_env_var	boolean	Exclude $TMPDIR from writable roots (default: false).
sandbox_workspace_write.exclude_slash_tmp	boolean	Exclude /tmp from writable roots (default: false).
notify	array	External program for notifications.
instructions	string	Currently ignored; use experimental_instructions_file or AGENTS.md.
mcp_servers.<id>.command	string	MCP server launcher command (stdio servers only).
mcp_servers.<id>.args	array	MCP server args (stdio servers only).
mcp_servers.<id>.env	map<string,string>	MCP server env vars (stdio servers only).
mcp_servers.<id>.url	string	MCP server url (streamable http servers only).
mcp_servers.<id>.bearer_token_env_var	string	environment variable containing a bearer token to use for auth (streamable http servers only).
mcp_servers.<id>.enabled	boolean	When false, Codex skips starting the server (default: true).
mcp_servers.<id>.startup_timeout_sec	number	Startup timeout in seconds (default: 10). Timeout is applied both for initializing MCP server and initially listing tools.
mcp_servers.<id>.tool_timeout_sec	number	Per-tool timeout in seconds (default: 60). Accepts fractional values; omit to use the default.
mcp_servers.<id>.enabled_tools	array	Restrict the server to the listed tool names.
mcp_servers.<id>.disabled_tools	array	Remove the listed tool names after applying enabled_tools, if any.
model_providers.<id>.name	string	Display name.
model_providers.<id>.base_url	string	API base URL.
model_providers.<id>.env_key	string	Env var for API key.
model_providers.<id>.wire_api	chat | responses	Protocol used (default: chat).
model_providers.<id>.query_params	map<string,string>	Extra query params (e.g., Azure api-version).
model_providers.<id>.http_headers	map<string,string>	Additional static headers.
model_providers.<id>.env_http_headers	map<string,string>	Headers sourced from env vars.
model_providers.<id>.request_max_retries	number	Per‑provider HTTP retry count (default: 4).
model_providers.<id>.stream_max_retries	number	SSE stream retry count (default: 5).
model_providers.<id>.stream_idle_timeout_ms	number	SSE idle timeout (ms) (default: 300000).
project_doc_max_bytes	number	Max bytes to read from AGENTS.md.
profile	string	Active profile name.
profiles.<name>.*	various	Profile‑scoped overrides of the same keys.
history.persistence	save-all | none	History file persistence (default: save-all).
history.max_bytes	number	Currently ignored (not enforced).
file_opener	vscode | vscode-insiders | windsurf | cursor | none	URI scheme for clickable citations (default: vscode).
tui	table	TUI‑specific options.
tui.notifications	boolean | array	Enable desktop notifications in the tui (default: false).
hide_agent_reasoning	boolean	Hide model reasoning events.
show_raw_agent_reasoning	boolean	Show raw reasoning (when available).
model_reasoning_effort	minimal | low | medium | high	Responses API reasoning effort.
model_reasoning_summary	auto | concise | detailed | none	Reasoning summaries.
model_verbosity	low | medium | high	GPT‑5 text verbosity (Responses API).
model_supports_reasoning_summaries	boolean	Force‑enable reasoning summaries.
model_reasoning_summary_format	none | experimental	Force reasoning summary format.
chatgpt_base_url	string	Base URL for ChatGPT auth flow.
experimental_instructions_file	string (path)	Replace built‑in instructions (experimental).
experimental_use_exec_command_tool	boolean	Use experimental exec command tool.
projects.<path>.trust_level	string	Mark project/worktree as trusted (only "trusted" is recognized).
tools.web_search	boolean	Enable web search tool (alias: web_search_request) (default: false).
forced_login_method	chatgpt | api	Only allow Codex to be used with ChatGPT or API keys.
forced_chatgpt_workspace_id	string (uuid)	Only allow Codex to be used with the specified ChatGPT workspace.
tools.view_image	boolean	Enable the view_image tool so Codex can attach local image files from the workspace (default: false).
