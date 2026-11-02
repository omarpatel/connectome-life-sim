# Licenses and attribution

## Code and upstream work

The code is distributed under the [MIT License](../LICENSE), copyright
Omar Patel. This source port preserves the engineering work of the original
**Instar upstream contributors**. Dataset authorship is separate from code
authorship; neither source credit implies endorsement of this port.

## Janelia FlyEM MaleCNS v1.0 dataset

Berg S., Beckett I.R., Costa M., Schlegel P., Januszewski M., Marin E.C.,
Nern A., and collaborators, including Jefferis G.S.X.E., *Sexual dimorphism
in the complete connectome of the Drosophila male central nervous system*.
[Preprint: doi:10.1101/2025.10.09.680999](https://doi.org/10.1101/2025.10.09.680999);
[Cell publication (2026)](https://www.cell.com/cell/fulltext/S0092-8674(26)00942-6).
Data release: Janelia FlyEM Male CNS connectome v1.0.

**Dataset license: [Creative Commons Attribution 4.0 International
(CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).**
The [official MaleCNS project page](https://male-cns.janelia.org/) states
“The Male CNS dataset is licensed under CC-BY” and links directly to that
license. The public page was consulted for this port on 2026-11-02; it also
links the v1.0 release, download documentation and publication. The code's
MIT license does not replace the dataset license.

The project credits FlyEM (HHMI Janelia), the University of Cambridge,
the MRC Laboratory of Molecular Biology and Google Research as collaborators.
No endorsement of Instar or this simulation by these institutions or the
dataset authors is claimed.

### Source files and modifications

`tools/census/malecns.py` downloads two files from the
[public flat-connectome bucket](https://storage.googleapis.com/flyem-male-cns?prefix=v1.0/connectome-data/flat-connectome/):

- `connectome-weights-male-cns-v1.0-minconf-0.5.feather`
- `body-annotations-male-cns-v1.0-minconf-0.5.feather`

The retained header, `data/canonical/male-cns-v1.0.census.json`, records their
source URLs, byte sizes and SHA-256 digests. The converter preserves the
166,700 bodies carrying a neuron `superclass` annotation and keeps directed
connections of at least five synapses between them. Synapse counts come from
the source export at confidence >= 0.5. Body annotations are converted to
canonical node records and connectivity to the CBG0 binary format. These are
**representation changes and a connectivity threshold**, not unmodified
redistribution of the original tables. Conversion details and the canonical
Merkle construction are specified in [SCHEMA.md](SCHEMA.md).

The binary graph is generated locally rather than committed because it
exceeds 50 MB. Fetch and conversion instructions are in the root README.
The header and node annotations remain attributed under CC BY 4.0; generated
derivatives retain the same source credit and modification notice. No
additional restrictions on the dataset are imposed by this repository.

### Scientific limitations

The dataset supplies wiring and synapse counts, not a validated dynamical
model. Instar adds simplified threshold neurons, sensory inputs, body
mechanics and reproduction. It does not reconstruct a biologically faithful
animal, and deterministic replay does not validate biological accuracy.

## Fonts and libraries

Instrument Serif and IBM Plex Mono use the SIL Open Font License; retain
`site/fonts/OFL-*.txt` with redistributed font files. The bundled three.js
library is MIT-licensed; retain its upstream notice in `site/vendor/`.
Other dependencies retain the notices and licenses distributed with them.
