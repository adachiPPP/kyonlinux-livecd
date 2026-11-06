# kyonlinux-os
an independent arch-based custom distribution with a custom package manager (nya) made from scratch designed with a focus on user-friendly accessibility and refined aesthetics

## Making a boot USB

This ISO is a hybrid image: the same bytes can boot BIOS and UEFI. For most people the simplest reliable options are:

- **dd on Linux** (whole device, not a partition):
  ```bash
  dd bs=4M if=kyonlinux-*.iso of=/dev/sdX conv=fsync oflag=direct status=progress
  sync
  ```
  Use the whole device path (`/dev/sdX`), not a partition (`/dev/sdX1`). After `dd`, run `sync`. If you do not `sync` before removing the drive, the end of the ISO may not be fully written and the live system can fail later at the installer's `unpackfs` step.

- **BalenaEtcher**: works like dd for this ISO (byte-for-byte write). If Etcher reports verification problems, re-flash; a bad verification usually means the write did not finish cleanly.

- **Rufus on Windows**: for this kind of hybrid/arch-style ISO, use **DD Image mode** if the default ISO Image mode does not boot correctly. DD mode is the safer path for hybrid isos that expect to be written byte-for-byte.

- **Ventoy**: copy the ISO file onto a Ventoy USB and boot it from the Ventoy menu. Ventoy boots the ISO by loopback, so the live system may not see the usual `/run/archiso/bootmnt/...` layout; this distro ships a `fix-boot-media` installer step that tries to find `airootfs.sfs` anyway.

### If the installer fails at "unpackfs"

The installer step that usually fails there is `unpackfs`, which unsquashes `airootfs.sfs` from the boot media into the target system. When that step fails, the cause is usually that the live system cannot find a readable `airootfs.sfs` on the USB.

Before blaming the ISO, check the live system:

```bash
ls -l /run/archiso/bootmnt/arch/x86_64/airootfs.sfs
file /run/archiso/bootmnt/arch/x86_64/airootfs.sfs

# if the path above does not exist, this distro's fix-boot-media step may have
# found it elsewhere; check its log:
journalctl -b -u calamares.service --no-pager | grep -i fix-boot-media || true
```

Common dd/USB causes:

- `dd` was pointed at a partition (`/dev/sdX1`) instead of the whole device.
- The USB was removed before `sync`, so the end of the ISO was not written.
- The USB is too small for the ISO, so the end of the image (and its squashfs superblock) was truncated.
- The USB is a 4Kn / Advanced Format device whose logical sector size is larger than 2048 bytes. Hybrid ISO images are not a good match for dd onto such devices.
- The ISO was written by a tool that does not write it byte-for-byte and does not preserve the layout the live initramfs expects.

If the path exists and `file` says it is a valid squashfs, the problem is likely in the installer or the target disk, not the USB.

