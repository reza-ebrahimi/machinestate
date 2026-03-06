package collectors

import (
	"github.com/shirou/gopsutil/v3/disk"

	"machinestate/models"
)

// CollectDiskInfo gathers filesystem information
func CollectDiskInfo() models.DiskInfo {
	info := models.DiskInfo{
		Filesystems: []models.Filesystem{},
	}

	// Get all partitions
	partitions, err := disk.Partitions(false)
	if err != nil {
		return info
	}

	// Filter to only include real filesystems
	for _, p := range partitions {
		// Skip virtual filesystems
		if isVirtualFS(p.Fstype) {
			continue
		}

		// Skip snap mounts
		if isSnapMount(p.Mountpoint) {
			continue
		}

		usage, err := disk.Usage(p.Mountpoint)
		if err != nil {
			continue
		}

		fs := models.Filesystem{
			Device:      p.Device,
			MountPoint:  p.Mountpoint,
			FSType:      p.Fstype,
			Total:       usage.Total,
			Used:        usage.Used,
			Free:        usage.Free,
			UsedPercent: usage.UsedPercent,
			InodesTotal: usage.InodesTotal,
			InodesUsed:  usage.InodesUsed,
			InodesFree:  usage.InodesFree,
		}

		if usage.InodesTotal > 0 {
			fs.InodesPercent = float64(usage.InodesUsed) / float64(usage.InodesTotal) * 100
		}

		info.Filesystems = append(info.Filesystems, fs)
	}

	return info
}

// isVirtualFS checks if the filesystem type is virtual
func isVirtualFS(fstype string) bool {
	virtualFS := map[string]bool{
		"proc":       true,
		"sysfs":      true,
		"devfs":      true,
		"devpts":     true,
		"tmpfs":      true,
		"securityfs": true,
		"cgroup":     true,
		"cgroup2":    true,
		"pstore":     true,
		"debugfs":    true,
		"hugetlbfs":  true,
		"mqueue":     true,
		"fusectl":    true,
		"configfs":   true,
		"binfmt_misc": true,
		"autofs":     true,
		"efivarfs":   true,
		"squashfs":   true, // Snap packages
	}
	return virtualFS[fstype]
}

// isSnapMount checks if the mount point is a snap mount
func isSnapMount(mountpoint string) bool {
	return len(mountpoint) > 5 && mountpoint[:5] == "/snap"
}
