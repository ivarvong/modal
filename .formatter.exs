# Used by "mix format"
[
  # 120 cols — modern default; matches the Python modal-client (ruff 120) and
  # Credo's MaxLineLength, so the formatter and linter agree.
  line_length: 120,
  inputs:
    ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"] --
      ["lib/modal/proto/**/*.ex"]
]
