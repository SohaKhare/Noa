# NYI org map (item 0.14)

The first org Noa runs on: NotYourIdea. This is the input for onboarding (1.18), the seed for the graph (`Person`, `Project`, `Channel`, `WORKS_ON`, `REPORTS_TO`, `MAPS_TO`), and the sample data in `web/src/lib/mock.ts`. The machine-readable copy is [`seeds/nyi.json`](seeds/nyi.json); change both together.

Status marks: **Confirmed** came from Saish. **From git** was read from commit history in `~/code/nyi` on Oct 16. **To confirm** is a guess; replace it with the real value before the seed is loaded.

## People and roles

| Person | Title | Noa role | Reports to | Status |
| --- | --- | --- | --- | --- |
| Ojas | Co-founder, tech | Org admin | none | Confirmed (title); role to confirm |
| Abhishek | Co-founder, content | Org admin | none | Confirmed (title); role to confirm |
| Vedant | SWE, PM / lead for the hackathon | Org admin | Ojas | Confirmed (lead); reports-to to confirm |
| Prathamesh | Head of AI, PM / lead | Org admin | Ojas | Confirmed (Oct 18); email assumed prathamesh@notyouridea.com |
| Saish | Intern, PM / lead | PM / lead | Vedant | Confirmed (title, role Oct 18); reports-to to confirm |
| Soha | Intern | Member | Vedant | Confirmed (title); reports-to to confirm |

Reports-to decides who approves deadline and scope changes (2.20), so it must be right before 2.19 ships.

Prathamesh (Head of AI) joined as an org admin and PM / lead on Oct 18, alongside Vedant; Saish is a PM / lead too.

## Projects

| Project | What it is | Repo | Lead | Status |
| --- | --- | --- | --- | --- |
| Veriq | AI reputation reports: how seven AI model families and Google AI Overview answer about a brand | `Not-Your-Idea/veriq` | Vedant | Lead set for the hackathon |
| Emmarie | Writing-first film workspace: screenplay, coverage, storyboard, motion test, final take | `Not-Your-Idea/emmarie` | Vedant | Lead set for the hackathon |
| Tulpa | Chat memory and decisions with sources. Noa's predecessor; its history is imported (1.12) | `Not-Your-Idea/tulpa` | Saish | From git; lead to confirm |
| Video Break | Research: why videos hold attention (hooks, beats, edits) | none yet (`video_break/` research notes) | Abhishek | To confirm |

Honcho (`~/code/nyi/honcho`) is Plastic Labs' open-source memory service that Tulpa uses, not an NYI project, so it is left out.

Tulpa v1's extractor was also told about client themes "AhaBazaar", "Unstumbled" and "Abhay Bhutada Foundation". If those are live client projects, add them here.

## Who works where (allocations)

From commit counts, Oct 16. Percentages are guesses until the team sets them in onboarding.

| Person | Veriq | Emmarie | Tulpa | Video Break | Status |
| --- | --- | --- | --- | --- | --- |
| Saish | 40% | 10% | 50% | | From git; split to confirm |
| Vedant | 20% | 40% | 40% | | From git (as "VedantNYI"); split to confirm |
| Soha | | | | 100% | To confirm |
| Abhishek | | | | 50% | To confirm |
| Ojas | | | | | To confirm |

A contributor "Rahul Yadav" has 11 commits on Veriq and is not in the people list. Confirm whether he should be added.

## Channels to projects

Noa only reads mapped channels and never reads DMs. Channel names below are the pattern used in the demo; replace them with the real Discord channel names during onboarding.

| Channel | Platform | Project | Read | Status |
| --- | --- | --- | --- | --- |
| `#veriq` | Discord | Veriq | yes | To confirm |
| `#emmarie` | Discord | Emmarie | yes | To confirm |
| `#tulpa` | Discord | Tulpa | yes | To confirm |
| `#video-break` | Discord | Video Break | yes | To confirm |
| `#dev` | Discord | split by message | yes | To confirm |
| `#general` | Discord | split by message | yes | To confirm |
| `#random` | Discord | none | no | To confirm |
| WhatsApp, Abhishek | WhatsApp (Kapso) | split by message | yes | To confirm |

"Split by message" means each message is routed on its own (see [extraction.md](extraction.md#routing-116)).

## Project aliases

Names people use in chat that should route to a project (1.16). Add to these as Noa sees new ones.

| Alias | Project |
| --- | --- |
| reports, the reports app, AI rep | Veriq |
| film app, screenplay app, emm | Emmarie |
| v1, the old bot | Tulpa |
| reels research, VB | Video Break |
