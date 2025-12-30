package collectors

import (
	"net"
	"os/exec"
	"strconv"
	"strings"
	"time"

	psnet "github.com/shirou/gopsutil/v3/net"

	"ubuntu-state/models"
)

// CollectNetworkInfo gathers network information
func CollectNetworkInfo() models.NetworkInfo {
	info := models.NetworkInfo{
		Interfaces:  []models.NetworkInterface{},
		ListenPorts: []models.ListenPort{},
	}

	// Get network interfaces
	interfaces, err := psnet.Interfaces()
	if err == nil {
		ioCounters, _ := psnet.IOCounters(true)
		ioMap := make(map[string]psnet.IOCountersStat)
		for _, io := range ioCounters {
			ioMap[io.Name] = io
		}

		for _, iface := range interfaces {
			// Skip loopback and virtual interfaces
			if iface.Name == "lo" || strings.HasPrefix(iface.Name, "veth") {
				continue
			}

			ni := models.NetworkInterface{
				Name:  iface.Name,
				State: getInterfaceState(iface.Flags),
				MAC:   iface.HardwareAddr,
				IPs:   []string{},
			}

			for _, addr := range iface.Addrs {
				ni.IPs = append(ni.IPs, addr.Addr)
			}

			if io, ok := ioMap[iface.Name]; ok {
				ni.RxBytes = io.BytesRecv
				ni.TxBytes = io.BytesSent
			}

			info.Interfaces = append(info.Interfaces, ni)
		}
	}

	// Get listening ports
	connections, err := psnet.Connections("all")
	if err == nil {
		seen := make(map[string]bool)
		for _, conn := range connections {
			if conn.Status != "LISTEN" {
				continue
			}

			key := conn.Laddr.IP + ":" + strconv.Itoa(int(conn.Laddr.Port))
			if seen[key] {
				continue
			}
			seen[key] = true

			port := models.ListenPort{
				Protocol: protocolName(conn.Type),
				Address:  conn.Laddr.IP,
				Port:     conn.Laddr.Port,
				PID:      conn.Pid,
			}

			// Get process name
			if conn.Pid > 0 {
				port.Process = getProcessName(conn.Pid)
			}

			info.ListenPorts = append(info.ListenPorts, port)
		}
	}

	// Check connectivity
	info.Connectivity = checkConnectivity()

	return info
}

// getInterfaceState returns the interface state from flags
func getInterfaceState(flags []string) string {
	for _, flag := range flags {
		if flag == "up" {
			return "UP"
		}
	}
	return "DOWN"
}

// protocolName converts protocol number to name
func protocolName(connType uint32) string {
	switch connType {
	case 1:
		return "TCP"
	case 2:
		return "UDP"
	default:
		return "UNKNOWN"
	}
}

// getProcessName gets the process name from PID
func getProcessName(pid int32) string {
	cmd := exec.Command("ps", "-p", strconv.Itoa(int(pid)), "-o", "comm=")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

// checkConnectivity tests internet connectivity
func checkConnectivity() bool {
	conn, err := net.DialTimeout("tcp", "8.8.8.8:53", 3*time.Second)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}
