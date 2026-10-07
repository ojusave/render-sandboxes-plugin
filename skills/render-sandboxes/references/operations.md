# Sandbox operations

Run these from the plugin root. `scripts/sandbox.sh` waits until a sandbox is `running` before exec, copy is not used as a wait, and snapshot waits until the snapshot is `available`.

```bash
bash scripts/sandbox.sh groups
bash scripts/sandbox.sh create --timeout 900 --network-policy deny-all
bash scripts/sandbox.sh create --timeout 900 --network-policy deny-all --snapshot-id snp-...
bash scripts/sandbox.sh inspect
bash scripts/sandbox.sh inspect sbx-...
bash scripts/sandbox.sh exec sbx-... -- python3 -c 'print("ok")'
bash scripts/sandbox.sh copy ./report.txt sbx-...:/workspace/report.txt
bash scripts/sandbox.sh copy sbx-...:/workspace/report.txt ./report.txt
bash scripts/sandbox.sh snapshot sbx-...
bash scripts/sandbox.sh snapshot sbx-... --kind runtime
bash scripts/sandbox.sh stop sbx-...
```

A relative remote path is inside the sandbox home directory. An absolute remote path starts at the sandbox filesystem root. Copy a directory's contents to the destination path; they are not nested one level deeper.

`stop` always passes `--confirm`. Without that flag the Render CLI only previews termination.
