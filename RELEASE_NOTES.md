# Release v5.1.2

## Changes in this Release

- **DNS Cache Clearing**:
  - Added a button on the control panel homepage to clear the DNS cache.
  - Optimized cache clearing logic to delete local persistent cache files on disk.
  - Integrated cache clearing to reset SQLite query logs and Prometheus statistics.
  - Corrected the API endpoint address used for cache clearing to the plugin's exclusive endpoint.

- **DNS Resolution Optimization**:
  - Moved local PTR and private domain resolution logic before the cache stage to allow configurations to take effect in real time.

- **Installation & Maintenance**:
  - Pointed the control panel binary download source in the installation scripts to the latest releases instead of the main branch.

- **Style & Cleanliness**:
  - Removed emojis, marketing fluff, and absolute claims from instructions, documentation, and user prompts.
