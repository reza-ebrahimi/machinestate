const std = @import("std");

pub const Severity = struct {
    pub const critical = "critical";
    pub const warning = "warning";
    pub const info = "info";
};

// Issue represents a detected system issue
pub const Issue = struct {
    severity: []const u8,
    category: []const u8,
    title: []const u8,
    description: []const u8,
    fix: ?[]const u8 = null,
};

// OSInfo contains operating system information
pub const OSInfo = struct {
    name: []const u8,
    version: []const u8,
    kernel: []const u8,
    architecture: []const u8,
};

// SystemInfo contains CPU, memory, and system metrics
pub const SystemInfo = struct {
    uptime: i64, // nanoseconds
    uptime_human: []const u8,
    timezone: []const u8,
    reboot_required: bool,
    load_avg_1: f64,
    load_avg_5: f64,
    load_avg_15: f64,
    cpu_cores: i32,
    cpu_usage: f64,
    memory_total: u64,
    memory_used: u64,
    memory_free: u64,
    memory_percent: f64,
    swap_total: u64,
    swap_used: u64,
    swap_percent: f64,
};

// Filesystem represents a mounted filesystem
pub const Filesystem = struct {
    device: []const u8,
    mount_point: []const u8,
    fs_type: []const u8,
    total: u64,
    used: u64,
    free: u64,
    used_percent: f64,
    inodes_total: u64,
    inodes_used: u64,
    inodes_free: u64,
    inodes_percent: f64,
};

// DiskInfo contains filesystem information
pub const DiskInfo = struct {
    filesystems: []const Filesystem,
};

// NetworkInterface represents a network interface
pub const NetworkInterface = struct {
    name: []const u8,
    state: []const u8,
    mac: []const u8,
    ips: []const []const u8,
    rx_bytes: u64,
    tx_bytes: u64,
};

// ListenPort represents a listening port
pub const ListenPort = struct {
    protocol: []const u8,
    address: []const u8,
    port: u32,
    process: []const u8,
    pid: i32,
};

// NetworkInfo contains network information
pub const NetworkInfo = struct {
    interfaces: []const NetworkInterface,
    listen_ports: []const ListenPort,
    connectivity: bool,
    public_ip: ?[]const u8 = null,
};

// PackageInfo contains APT package information
pub const PackageInfo = struct {
    updates_available: i32,
    updates_list: ?[]const []const u8 = null,
    security_updates: i32,
    broken_packages: i32,
    held_packages: ?[]const []const u8 = null,
};

// ProcessInfo represents a process
pub const ProcessInfo = struct {
    pid: i32,
    name: []const u8,
    cpu: f64,
    memory: f32,
    user: []const u8,
};

// ServiceInfo contains systemd service information
pub const ServiceInfo = struct {
    failed_units: []const []const u8,
    zombie_count: i32,
    top_cpu: []const ProcessInfo,
    top_memory: []const ProcessInfo,
};

// SecurityInfo contains security-related information
pub const SecurityInfo = struct {
    firewall_active: bool,
    firewall_status: []const u8,
    failed_logins_24h: i32,
    open_ports: []const []const u8,
    ssh_enabled: bool,
};

// BatteryInfo contains battery information
pub const BatteryInfo = struct {
    present: bool,
    status: []const u8,
    capacity: f64,
    health: f64,
    cycle_count: i32,
    design_capacity: f64,
    full_capacity: f64,
};

// TemperatureInfo contains temperature sensor information
pub const TemperatureInfo = struct {
    label: []const u8,
    current: f64,
    high: ?f64 = null,
    critical: ?f64 = null,
};

// HardwareInfo contains hardware information
pub const HardwareInfo = struct {
    battery: ?BatteryInfo = null,
    temperatures: ?[]const TemperatureInfo = null,
    crash_reports: ?[]const []const u8 = null,
};

// ContainerInfo represents a Docker container
pub const ContainerInfo = struct {
    name: []const u8,
    image: []const u8,
    status: []const u8,
    state: []const u8,
    created: []const u8 = "",
    cpu_percent: f64 = 0,
    memory_percent: f64 = 0,
};

// DockerInfo contains Docker information
pub const DockerInfo = struct {
    available: bool,
    daemon_running: bool = false,
    containers: ?[]const ContainerInfo = null,
    running_count: i32 = 0,
    stopped_count: i32 = 0,
    image_count: i32 = 0,
    total_image_size: i64 = 0,
    dangling_images_size: i64 = 0,
};

pub const SnapPackage = struct {
    name: []const u8,
    version: []const u8,
    revision: []const u8,
    publisher: []const u8,
    disk_usage: i64 = 0,
};

pub const SnapInfo = struct {
    available: bool,
    snaps: ?[]const SnapPackage = null,
    total_disk_usage: i64 = 0,
    pending_refreshes: i32 = 0,
};

pub const GPUDevice = struct {
    index: i32,
    name: []const u8,
    vendor: []const u8,
    temperature: i32 = 0,
    utilization: i32 = 0,
    memory_used: i64 = 0,
    memory_total: i64 = 0,
    power_draw: f64 = 0,
};

pub const GPUInfo = struct {
    available: bool,
    gpus: ?[]const GPUDevice = null,
};

pub const ErrorPattern = struct {
    pattern: []const u8,
    count: i32,
};

pub const LogStats = struct {
    error_count: i32 = 0,
    warning_count: i32 = 0,
    critical_count: i32 = 0,
    oom_events: i32 = 0,
    kernel_panics: i32 = 0,
    segfaults: i32 = 0,
    top_errors: ?[]const ErrorPattern = null,
};

pub const LogInfo = struct {
    available: bool,
    period: []const u8 = "24h",
    stats: LogStats,
};

// Report is the main system state report
pub const Report = struct {
    timestamp: []const u8, // RFC3339 format
    hostname: []const u8,
    os: OSInfo,
    system: SystemInfo,
    disk: DiskInfo,
    network: NetworkInfo,
    packages: PackageInfo,
    services: ServiceInfo,
    security: SecurityInfo,
    hardware: HardwareInfo,
    docker: ?DockerInfo = null,
    snaps: ?SnapInfo = null,
    gpu: ?GPUInfo = null,
    logs: ?LogInfo = null,
    issues: []const Issue,
};

// Helper function to create a default/empty Report
pub fn emptyReport() Report {
    return Report{
        .timestamp = "",
        .hostname = "",
        .os = OSInfo{
            .name = "",
            .version = "",
            .kernel = "",
            .architecture = "",
        },
        .system = SystemInfo{
            .uptime = 0,
            .uptime_human = "",
            .timezone = "",
            .reboot_required = false,
            .load_avg_1 = 0,
            .load_avg_5 = 0,
            .load_avg_15 = 0,
            .cpu_cores = 0,
            .cpu_usage = 0,
            .memory_total = 0,
            .memory_used = 0,
            .memory_free = 0,
            .memory_percent = 0,
            .swap_total = 0,
            .swap_used = 0,
            .swap_percent = 0,
        },
        .disk = DiskInfo{ .filesystems = &[_]Filesystem{} },
        .network = NetworkInfo{
            .interfaces = &[_]NetworkInterface{},
            .listen_ports = &[_]ListenPort{},
            .connectivity = false,
            .public_ip = null,
        },
        .packages = PackageInfo{
            .updates_available = 0,
            .updates_list = null,
            .security_updates = 0,
            .broken_packages = 0,
            .held_packages = null,
        },
        .services = ServiceInfo{
            .failed_units = &[_][]const u8{},
            .zombie_count = 0,
            .top_cpu = &[_]ProcessInfo{},
            .top_memory = &[_]ProcessInfo{},
        },
        .security = SecurityInfo{
            .firewall_active = false,
            .firewall_status = "",
            .failed_logins_24h = 0,
            .open_ports = &[_][]const u8{},
            .ssh_enabled = false,
        },
        .hardware = HardwareInfo{
            .battery = null,
            .temperatures = null,
            .crash_reports = null,
        },
        .docker = null,
        .snaps = null,
        .gpu = null,
        .logs = null,
        .issues = &[_]Issue{},
    };
}
