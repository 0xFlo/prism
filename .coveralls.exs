# Test Coverage Configuration
#
# Philosophy: We measure business behavior coverage, not just line coverage.
# Focus on testing user journeys and critical algorithms rather than trivial code.

%{
  # Set minimum coverage threshold (start at 60%, target 80%)
  coverage_options: [
    minimum_coverage: 60,
    # Fail CI if coverage drops below threshold
    treat_no_relevant_lines_as_covered: true
  ],

  # Exclude files from coverage reports
  # Skip generated files, test support, and configuration
  skip_files: [
    # Generated Phoenix files
    "lib/gsc_analytics_web/telemetry.ex",
    "lib/gsc_analytics_web/endpoint.ex",
    "lib/gsc_analytics_web/router.ex",
    "lib/gsc_analytics_web/gettext.ex",

    # Application bootstrap
    "lib/gsc_analytics/application.ex",
    "lib/gsc_analytics/repo.ex",

    # Test support modules (these ARE tested, but indirectly)
    "test/support",

    # Mix tasks (these are CLI tools, test manually)
    "lib/mix/tasks",

    # Configuration helpers (simple, no business logic)
    "lib/gsc_analytics/data_sources/gsc/core/config.ex",

    # View components (test through LiveView integration tests)
    "lib/gsc_analytics_web/components",

    # Error views (Phoenix generated)
    "lib/gsc_analytics_web/controllers/error_"
  ]
}
