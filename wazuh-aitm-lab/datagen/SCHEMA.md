# AiTM dataset schema (shared contract)

The data generator (`datagen/generate.sh`) and the detection rules
(`custom-rules/aitm_rules.xml`) **must** agree on these field names. Change one,
change the other.

## entra_signin.json  (JSON, built-in `json` decoder)
| field | example | used by rule |
|-------|---------|--------------|
| `log_source` | `entra_signin` | 100100 |
| `timestamp` | `2025-04-14T09:12:33Z` | — |
| `user`→`dstuser` | `j.rivera` | correlation |
| `src_ip` | `203.0.113.45` | — |
| `geo_city` / `geo_country` | `Kyiv` / `UA` | — |
| `mfa_result` | `satisfiedByToken` | 100102 |
| `mfa_prompted` | `false` | 100102 |
| `session_id` | `sess-stolen-aitm-0001` | 100104 |
| `session_reuse` | `true` | 100104 |
| `impossible_travel` | `true` | 100103 |
| `anonymizer` | `true` | 100101 |
| `result` | `success` | 100101/100102 |

## m365_mailbox.json  (JSON)
| field | example | used by rule |
|-------|---------|--------------|
| `log_source` | `m365_mailbox` | 100110 |
| `operation` | `New-InboxRule` / `Set-Mailbox` | 100111 / 100112 |
| `rule_name` | `.` | 100111 |
| `forward_to` | `exfil-collector@mailsec-proxy.ru` | 100111/100112 |
| `user`→`dstuser` | `j.rivera@northwind-trading.com` | correlation |

## endpoint.json  (JSON)
| field | example | used by rule |
|-------|---------|--------------|
| `log_source` | `endpoint` | 100130 |
| `log_event` | `powershell` / `directory_recon` | 100131 / 100132 |
| `host` | `LT-RIVERA-01` | — |
| `command_line` | `IEX (New-Object Net.WebClient)...` | — |

## evilginx.log  (text, `custom-decoders/aitm_decoders.xml`)
Line: `evilginx: ts=.. src=.. method=.. uri=.. status=.. portal=.. user=.. creds=.. cookie=.. ua=".."`
| decoded field | used by rule |
|---------------|--------------|
| `srcip` | — |
| `portal` | 100121 |
| `user`→`dstuser` | 100121 |
| `creds_relayed` (`creds=`) | 100121 |
| `session_cookie` (`cookie=`) | 100122 |
