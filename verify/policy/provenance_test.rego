# Tests de la politique : conftest verify --policy verify/policy
package main

import rego.v1

digest := "8ae83e5b11e4cc8257f5f4d1023081ba1c72e8e60e8ed6cacd0d53a4ca2d142b"

good := {
	"expected": {
		"digest": digest,
		"builder_id": "https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@refs/tags/v2.1.0",
		"source_repo": "github.com/groupe/s2-keyless-slsa",
		"branch": "main",
		"workflow_path": ".github/workflows/release.yml",
		"allowed_events": ["push"],
	},
	"statement": {
		"_type": "https://in-toto.io/Statement/v0.1",
		"predicateType": "https://slsa.dev/provenance/v0.2",
		"subject": [{"name": "ghcr.io/groupe/s2-keyless-slsa", "digest": {"sha256": digest}}],
		"predicate": {
			"builder": {"id": "https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@refs/tags/v2.1.0"},
			"invocation": {
				"configSource": {
					"uri": "git+https://github.com/groupe/s2-keyless-slsa@refs/heads/main",
					"digest": {"sha1": "e491e4b2ce5bc76fb103729b61b04d3c46d8a192"},
					"entryPoint": ".github/workflows/release.yml",
				},
				"environment": {"github_event_name": "push"},
			},
		},
	},
}

test_provenance_conforme_admise if {
	count(deny) == 0 with input as good
}

test_autre_depot_refuse if {
	bad := json.patch(good, [{"op": "replace", "path": "/statement/predicate/invocation/configSource/uri", "value": "git+https://github.com/attaquant/s2-keyless-slsa@refs/heads/main"}])
	count(deny) == 1 with input as bad
}

test_autre_branche_refusee if {
	bad := json.patch(good, [{"op": "replace", "path": "/statement/predicate/invocation/configSource/uri", "value": "git+https://github.com/groupe/s2-keyless-slsa@refs/heads/feature"}])
	count(deny) == 1 with input as bad
}

test_autre_workflow_refuse if {
	bad := json.patch(good, [{"op": "replace", "path": "/statement/predicate/invocation/configSource/entryPoint", "value": ".github/workflows/debug.yml"}])
	count(deny) == 1 with input as bad
}

test_declencheur_manuel_refuse if {
	bad := json.patch(good, [{"op": "replace", "path": "/statement/predicate/invocation/environment/github_event_name", "value": "workflow_dispatch"}])
	count(deny) == 1 with input as bad
}

test_generateur_non_approuve_refuse if {
	bad := json.patch(good, [{"op": "replace", "path": "/statement/predicate/builder/id", "value": "https://github.com/attaquant/faux-generateur/.github/workflows/gen.yml@refs/tags/v1.0.0"}])
	count(deny) == 1 with input as bad
}

test_digest_different_refuse if {
	bad := json.patch(good, [{"op": "replace", "path": "/expected/digest", "value": "0000000000000000000000000000000000000000000000000000000000000000"}])
	count(deny) == 1 with input as bad
}

test_commit_absent_refuse if {
	bad := json.patch(good, [{"op": "remove", "path": "/statement/predicate/invocation/configSource/digest"}])
	count(deny) == 1 with input as bad
}

test_type_v1_refuse if {
	bad := json.patch(good, [{"op": "replace", "path": "/statement/predicateType", "value": "https://slsa.dev/provenance/v1"}])
	count(deny) == 1 with input as bad
}
