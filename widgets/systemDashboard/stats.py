#!/usr/bin/env python3
"""Print one JSON line of system stats per second for the dashboard."""
import ctypes
import glob
import json
import os
import sys
import time

# hwmon numbers can change between boots, so sensors are found by name: the first one present wins.
# temp1 is the package / die temperature on each: coretemp (Intel), k10temp and zenpower (AMD, Tctl),
# cpu_thermal (Raspberry Pi and other ARM boards).
SENSORS = {"cpu": ["coretemp", "k10temp", "zenpower", "cpu_thermal"]}

# Seconds between the slower readings (the rest update every second).
PROC_EVERY = 3    # top processes: scanning /proc costs ~5-10 ms
GPU_EVERY = 2     # GPU load, temperature and VRAM: ~3 ms of driver calls
POWER_EVERY = 10  # GPU power and clock: ~10 ms, mostly nvmlDeviceGetPowerUsage
DISK_EVERY = 30   # root filesystem use: it changes slowly


def read(path):
    with open(path) as f:
        return f.read()


def cpu_times():
    """(idle, total) jiffies for the whole CPU."""
    v = [int(x) for x in read("/proc/stat").splitlines()[0].split()[1:]]
    return v[3] + v[4], sum(v[:8])  # idle + iowait; guest time is already in user/nice


def usage(prev, cur):
    idle, total = cur[0] - prev[0], cur[1] - prev[1]
    return round(100 * (1 - idle / total), 1) if total else 0.0


def memory():
    m = {}
    for line in read("/proc/meminfo").splitlines():
        key, val = line.split(":")
        m[key] = int(val.split()[0]) / 1048576  # kB -> GiB
    return {
        "used": round(m["MemTotal"] - m["MemAvailable"], 2),
        "total": round(m["MemTotal"], 2),
    }


def disk(path="/"):
    """{used, total} GiB of the filesystem at path, counted like df (used = total - free)."""
    st = os.statvfs(path)
    return {
        "used": round((st.f_blocks - st.f_bfree) * st.f_frsize / 1073741824, 1),
        "total": round(st.f_blocks * st.f_frsize / 1073741824, 1),
    }


def battery_dir():
    """The first battery's /sys directory, or None (a desktop)."""
    found = sorted(glob.glob("/sys/class/power_supply/BAT*"))
    return found[0] if found else None


def battery(d):
    """{pct, status, watts}: watts from power_now, or current_now x voltage_now (µA x µV) when a battery lacks it."""
    try:
        pct, status = int(read(d + "/capacity")), read(d + "/status").strip()
    except (OSError, ValueError):
        return None
    try:
        uw = int(read(d + "/power_now"))
    except (OSError, ValueError):
        try:
            uw = int(read(d + "/current_now")) * int(read(d + "/voltage_now")) / 1e6
        except (OSError, ValueError):
            uw = None
    return {"pct": pct, "status": status, "watts": round(abs(uw) / 1e6, 1) if uw is not None else None}


def temps():
    names = {}
    for d in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            names[read(d + "/name").strip()] = d
        except OSError:
            pass
    out = {}
    for key, candidates in SENSORS.items():
        out[key] = None
        for name in candidates:
            try:
                out[key] = int(read(names[name] + "/temp1_input")) / 1000
                break
            except (KeyError, OSError, ValueError):
                pass
    return out


def net_bytes():
    """(rx, tx) bytes summed over physical interfaces, so bridges and tunnels aren't counted twice."""
    rx = tx = 0
    for line in read("/proc/net/dev").splitlines()[2:]:
        name, data = line.split(":", 1)
        if not os.path.exists("/sys/class/net/%s/device" % name.strip()):
            continue
        v = data.split()
        rx += int(v[0])
        tx += int(v[8])
    return rx, tx


def proc_times():
    """{pid: (name, utime + stime jiffies)} for every process.

    Raw os.open/os.read on bytes, about twice as fast as open().read() over ~300 processes.
    """
    out = {}
    for entry in os.scandir("/proc"):
        pid = entry.name
        if not pid.isdigit():
            continue
        try:
            fd = os.open("/proc/" + pid + "/stat", os.O_RDONLY)
            try:
                s = os.read(fd, 1024)
            finally:
                os.close(fd)
        except OSError:
            continue  # exited while scanning
        end = s.rindex(b")")  # the name can contain spaces and parentheses
        f = s[end + 2:].split(None, 14)
        out[pid] = (s[s.index(b"(") + 1:end], int(f[11]) + int(f[12]))
    return out


def top_procs(prev, cur, dt, n=3):
    """The n busiest process names (summed over same-named processes), as % of the whole CPU."""
    by_name = {}
    for pid, (name, t) in cur.items():
        if pid in prev:
            by_name[name] = by_name.get(name, 0) + t - prev[pid][1]
    scale = 100 / (dt * os.sysconf("SC_CLK_TCK") * os.cpu_count())
    top = sorted(by_name.items(), key=lambda kv: -kv[1])[:n]
    return [{"name": name.decode(errors="replace"), "cpu": round(j * scale, 1)} for name, j in top]


class _Util(ctypes.Structure):
    _fields_ = [("gpu", ctypes.c_uint), ("memory", ctypes.c_uint)]


class _Mem(ctypes.Structure):
    _fields_ = [("total", ctypes.c_ulonglong), ("free", ctypes.c_ulonglong), ("used", ctypes.c_ulonglong)]


def nvidia_pm():
    """The runtime power status file of the first NVIDIA display device, or None."""
    for d in sorted(glob.glob("/sys/bus/pci/devices/*")):
        try:
            if read(d + "/vendor").strip() == "0x10de" and read(d + "/class").startswith("0x03"):
                return d + "/power/runtime_status"
        except OSError:
            pass
    return None


def asleep(pm):
    """True while the GPU is runtime-suspended (Optimus laptops): a query would wake it and cost battery."""
    try:
        return pm is not None and read(pm).strip() == "suspended"
    except OSError:
        return False


def nvml_open():
    """(lib, handle, name) for GPU 0 through NVML, the library nvidia-smi uses, or None without one.

    Calling it in-process is far cheaper than starting nvidia-smi every second.
    """
    try:
        lib = ctypes.CDLL("libnvidia-ml.so.1")
    except OSError:
        return None
    handle = ctypes.c_void_p()
    if lib.nvmlInit_v2() or lib.nvmlDeviceGetHandleByIndex_v2(0, ctypes.byref(handle)):
        return None
    name = ctypes.create_string_buffer(96)
    lib.nvmlDeviceGetName(handle, name, 96)
    return lib, handle, name.value.decode().replace("NVIDIA ", "").replace("GeForce ", "")


def nv_uint(fn, *args):
    v = ctypes.c_uint()
    return v.value if fn(*args, ctypes.byref(v)) == 0 else None


def gpu(nv):
    """Load %, temperature and VRAM, read every GPU_EVERY seconds."""
    lib, h, name = nv
    u, m = _Util(), _Mem()
    ok_u = lib.nvmlDeviceGetUtilizationRates(h, ctypes.byref(u)) == 0
    ok_m = lib.nvmlDeviceGetMemoryInfo(h, ctypes.byref(m)) == 0
    return {
        "name": name,
        "util": u.gpu if ok_u else None,
        "temp": nv_uint(lib.nvmlDeviceGetTemperature, h, 0),  # 0 = the GPU die
        "memUsed": round(m.used / 1073741824, 2) if ok_m else None,
        "memTotal": round(m.total / 1073741824, 2) if ok_m else None,
    }


def gpu_slow(nv):
    """Power draw and graphics clock, read every POWER_EVERY seconds."""
    lib, h, _ = nv
    mw = nv_uint(lib.nvmlDeviceGetPowerUsage, h)
    return {
        "watts": round(mw / 1000, 1) if mw is not None else None,
        "mhz": nv_uint(lib.nvmlDeviceGetClockInfo, h, 0),  # 0 = graphics clock
    }


def mhz():
    freqs = []
    for f in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq"):
        try:
            freqs.append(int(read(f)))
        except (OSError, ValueError):
            pass
    return round(sum(freqs) / len(freqs) / 1000) if freqs else None


def main():
    # Opened while the GPU is awake (opening it wakes the card); until then it's tried on each GPU tick.
    pm = nvidia_pm()
    has_nvml = os.path.exists("/proc/driver/nvidia")  # the proprietary driver, not nouveau
    nv = None if asleep(pm) else nvml_open()
    prev, prev_net, prev_t = cpu_times(), net_bytes(), time.monotonic()
    prev_procs, procs_t = proc_times(), prev_t
    top, fast, slow = [], {}, {}
    bat, disk_info = battery_dir(), None
    time.sleep(0.5)
    tick = 0
    while True:
        cur, cur_net, t = cpu_times(), net_bytes(), time.monotonic()
        dt = t - prev_t
        rx, tx = (max(0, c - p) / dt for p, c in zip(prev_net, cur_net))
        cpu = usage(prev, cur)
        prev, prev_net, prev_t = cur, cur_net, t
        if tick % PROC_EVERY == 0:
            cur_procs = proc_times()
            top = top_procs(prev_procs, cur_procs, t - procs_t)
            prev_procs, procs_t = cur_procs, t
        if tick % DISK_EVERY == 0:
            try:
                disk_info = disk()
            except OSError:
                disk_info = None
        sleeping = asleep(pm)
        if sleeping:
            fast, slow = {"name": nv[2] if nv else "", "asleep": True}, {}
        else:
            if not nv and has_nvml and tick % GPU_EVERY == 0:
                nv = nvml_open()
            if nv and tick % GPU_EVERY == 0:
                fast = gpu(nv)
            if nv and tick % POWER_EVERY == 0:
                slow = gpu_slow(nv)
        print(json.dumps({
            "cpu": cpu,
            "net": {"rx": round(rx), "tx": round(tx)},  # bytes/s
            "mhz": mhz(),
            "mem": memory(),
            "temps": temps(),
            "gpu": {**fast, **slow} if nv or sleeping else None,
            "top": top,
            "disk": disk_info,
            "battery": battery(bat) if bat else None,  # None on a desktop
            "uptime": int(float(read("/proc/uptime").split()[0])),
        }), flush=True)
        tick += 1
        time.sleep(1)


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
