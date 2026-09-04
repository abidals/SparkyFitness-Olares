{{/*
SPARKY_FITNESS_API_ENCRYPTION_KEY + BETTER_AUTH_SECRET have no external source, so
the chart mints them once. `lookup` returns nothing while linting (no cluster), so
the else branch must always produce a value; on every later render the stored value
is read back and reused, so upgrades — and reinstalls, thanks to the resource-policy
keep annotation on the Secret — keep decrypting existing API keys and sessions.

To rotate on purpose: delete the sparkyfitness-app Secret in the app namespace and
upgrade. That deliberately invalidates stored encrypted API keys and all sessions.
*/}}
{{- define "sparkyfitness.apiEncryptionKey" -}}
{{- $existing := (lookup "v1" "Secret" .Release.Namespace "sparkyfitness-app") -}}
{{- if and $existing $existing.data (index $existing.data "SPARKY_FITNESS_API_ENCRYPTION_KEY") -}}
{{- index $existing.data "SPARKY_FITNESS_API_ENCRYPTION_KEY" | b64dec -}}
{{- else -}}
{{- randAlphaNum 64 -}}
{{- end -}}
{{- end }}

{{- define "sparkyfitness.betterAuthSecret" -}}
{{- $existing := (lookup "v1" "Secret" .Release.Namespace "sparkyfitness-app") -}}
{{- if and $existing $existing.data (index $existing.data "BETTER_AUTH_SECRET") -}}
{{- index $existing.data "BETTER_AUTH_SECRET" | b64dec -}}
{{- else -}}
{{- randAlphaNum 64 -}}
{{- end -}}
{{- end }}
