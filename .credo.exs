%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: ["lib/modal/proto/"]
      },
      checks: %{
        disabled: [
          {Credo.Check.Readability.WithSingleClause, []}
        ]
      }
    }
  ]
}
