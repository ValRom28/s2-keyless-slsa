# Politique d'admission : la provenance SLSA doit decrire exactement
# le build attendu. slsa-verifier a deja verifie la signature de la provenance,
# le generateur et le depot source ; ces regles ajoutent les exigences
# de l'organisation (workflow, evenement, commit, digest).
package main

import rego.v1

statement := input.statement

predicate := statement.predicate

expected := input.expected

deny contains msg if {
	statement.predicateType != "https://slsa.dev/provenance/v0.2"
	msg := sprintf("type de provenance inattendu : %v", [statement.predicateType])
}

deny contains msg if {
	predicate.builder.id != expected.builder_id
	msg := sprintf("generateur non approuve : %v", [predicate.builder.id])
}

deny contains msg if {
	want := sprintf("git+https://%s@refs/heads/%s", [expected.source_repo, expected.branch])
	predicate.invocation.configSource.uri != want
	msg := sprintf("source inattendue : %v (attendu %v)", [predicate.invocation.configSource.uri, want])
}

deny contains msg if {
	predicate.invocation.configSource.entryPoint != expected.workflow_path
	msg := sprintf("workflow inattendu : %v", [predicate.invocation.configSource.entryPoint])
}

deny contains msg if {
	event := predicate.invocation.environment.github_event_name
	not event in expected.allowed_events
	msg := sprintf("declencheur non autorise : %v", [event])
}

deny contains msg if {
	not regex.match(`^[a-f0-9]{40}$`, object.get(predicate.invocation.configSource, ["digest", "sha1"], ""))
	msg := "commit source absent de la provenance"
}

deny contains msg if {
	not subject_matches
	msg := sprintf("la provenance ne couvre pas le digest %v", [expected.digest])
}

subject_matches if {
	some s in statement.subject
	s.digest.sha256 == expected.digest
}
