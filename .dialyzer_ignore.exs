# Dialyzer mis-types Port.open/2 with our option list: OTP's open_port option
# spec is incomplete (bare :line / :stderr_to_stdout are runtime-valid but not
# in the typespec), so dialyzer infers open_port/2 can only return {:error, _}
# and flags the {:ok, port} branch as unreachable. Runtime-verified green by
# test/tdl/tdl_test.exs, which opens real ports via /bin/cat. Safe to ignore.
[
  {"lib/tdl/backend.ex", :pattern_match}
]
