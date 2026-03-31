# Barrier 延迟优化指南

## 🔴 高优先级优化

### 1. 网络延迟优化

#### ✅ TCP_NODELAY（已实现）
```cpp
// 已在 TCPSocket.cpp:316 启用
ARCH->setNoDelayOnSocket(m_socket, true);
```
这禁用了 Nagle 算法，确保鼠标移动等小数据包立即发送。

#### 🟡 建议：调整 Socket 缓冲区大小
```cpp
// 在 TCPSocket::init() 中添加
int sndbuf = 256 * 1024;  // 256KB 发送缓冲区
int rcvbuf = 256 * 1024;  // 256KB 接收缓冲区
setsockopt(m_socket->m_fd, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof(sndbuf));
setsockopt(m_socket->m_fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));
```
**效果**：减少内核缓冲区满导致的延迟

---

### 2. 事件循环优化

#### 🟡 建议：减少 poll 超时时间
**文件**: `src/lib/arch/unix/ArchNetworkBSD.cpp`

当前代码使用默认超时，建议：
```cpp
// 使用更短的超时时间（例如 10ms）以获得更低延迟
int pollSocket(PollEntry[], int num, double timeout) {
    // 对于输入处理，使用更短的超时
    if (timeout < 0 || timeout > 0.01) {
        timeout = 0.01;  // 最多等待 10ms
    }
    // ... 原有代码
}
```

#### 🟡 建议：使用忙等待模式（可选）
对于对延迟极度敏感的场景：
```cpp
// 添加配置选项：低延迟模式
bool g_lowLatencyMode = true;

// 在事件循环中
if (g_lowLatencyMode) {
    // 忙等待，不 sleep
    while (!hasEvent()) {
        // 短暂自旋
        for (volatile int i = 0; i < 100; i++);
    }
}
```

---

### 3. 输入批处理优化

#### 🟡 建议：鼠标移动事件批处理
**文件**: `src/lib/platform/MSWindowsScreen.cpp` 或 `src/lib/platform/XWindowsScreen.cpp`

当前：每个鼠标移动都发送网络消息
优化：累积多个鼠标移动再批量发送

```cpp
class MouseMotionBatcher {
private:
    SInt32 m_accumulatedX = 0;
    SInt32 m_accumulatedY = 0;
    std::chrono::time_point m_lastSend;
    const std::chrono::milliseconds BATCH_INTERVAL{1}; // 1ms

public:
    void onMouseMove(SInt32 dx, SInt32 dy) {
        m_accumulatedX += dx;
        m_accumulatedY += dy;
        
        auto now = std::chrono::steady_clock::now();
        if (now - m_lastSend >= BATCH_INTERVAL) {
            flush();
        }
    }
    
    void flush() {
        if (m_accumulatedX != 0 || m_accumulatedY != 0) {
            sendMouseMotion(m_accumulatedX, m_accumulatedY);
            m_accumulatedX = 0;
            m_accumulatedY = 0;
            m_lastSend = std::chrono::steady_clock::now();
        }
    }
};
```

**权衡**：延迟 vs 网络带宽

---

### 4. 内存管理优化

#### 🟡 建议：使用内存池
**文件**: 多处使用 `new/delete` 的地方

当前：频繁分配释放小块内存
优化：使用对象池

```cpp
template<typename T, size_t PoolSize = 1024>
class ObjectPool {
    std::array<T, PoolSize> pool;
    std::queue<T*> available;
    std::mutex mutex;
    
public:
    ObjectPool() {
        for (auto& obj : pool) {
            available.push(&obj);
        }
    }
    
    T* acquire() {
        std::lock_guard<std::mutex> lock(mutex);
        if (available.empty()) return nullptr;
        T* obj = available.front();
        available.pop();
        return obj;
    }
    
    void release(T* obj) {
        std::lock_guard<std::mutex> lock(mutex);
        available.push(obj);
    }
};

// 用于 Event 对象
ObjectPool<Event, 1024> g_eventPool;
```

---

### 5. 锁优化

#### 🟡 建议：使用读写锁
**文件**: `src/lib/net/SocketMultiplexer.cpp`

当前使用 `Mutex`，建议：
```cpp
// 替换
std::mutex m_mutex;
// 为
std::shared_mutex m_mutex;  // C++17

// 读操作使用 shared_lock
std::shared_lock<std::shared_mutex> lock(m_mutex);

// 写操作使用 unique_lock
std::unique_lock<std::shared_mutex> lock(m_mutex);
```

#### 🟡 建议：无锁队列
**文件**: `src/lib/base/SimpleEventQueueBuffer.cpp`

使用 lock-free 队列替代 mutex：
```cpp
#include <boost/lockfree/spsc_queue.hpp>

// 单生产者单消费者无锁队列
boost::lockfree::spsc_queue<Event, boost::lockfree::capacity<1024>> m_queue;
```

---

## 🟡 中优先级优化

### 6. 协议优化

#### 🟡 建议：压缩鼠标移动数据
当前协议开销较大，可以：
```cpp
// 当前：每个鼠标移动发送完整数据包
// 优化：使用增量编码
struct MouseDelta {
    int8_t dx;      // 1字节
    int8_t dy;      // 1字节
    uint8_t flags;  // 1字节
};

// 对于大移动，使用变长编码
void encodeMouseMotion(SInt32 dx, SInt32 dy) {
    if (dx >= -128 && dx <= 127 && dy >= -128 && dy <= 127) {
        // 使用压缩格式
        sendCompressed(dx, dy);
    } else {
        // 使用完整格式
        sendFull(dx, dy);
    }
}
```

### 7. 剪贴板同步优化

#### 🟡 建议：延迟同步大剪贴板
**文件**: `src/lib/barrier/Clipboard.cpp`

```cpp
// 对于大剪贴板内容，使用延迟同步
void onClipboardChanged() {
    if (clipboardSize > 1024 * 1024) {  // > 1MB
        // 延迟 500ms，等待用户完成复制
        scheduleDelayedSync(500);
    } else {
        syncImmediately();
    }
}
```

### 8. CPU 亲和性

#### 🟡 建议：绑定到特定 CPU 核心
```cpp
#ifdef __linux__
#include <sched.h>

void setCpuAffinity(int cpu) {
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpuset), &cpuset);
}

// 在主线程启动时
setCpuAffinity(0);  // 绑定到 CPU 0
#endif
```

---

## 🟢 低优先级优化

### 9. 日志优化

#### 🟢 建议：异步日志
当前日志可能阻塞主线程，建议：
```cpp
class AsyncLogger {
    std::thread logThread;
    boost::lockfree::spsc_queue<std::string> logQueue;
    
public:
    void log(const std::string& msg) {
        logQueue.push(msg);  // 非阻塞
    }
};
```

### 10. 编译优化

#### 🟢 建议：使用 LTO（链接时优化）
```cmake
# CMakeLists.txt
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -march=native")
```

---

## 📊 性能测试建议

### 测量延迟的工具
```bash
# 1. 网络延迟测试
ping -c 100 <client-ip>

# 2. 使用 tcpdump 分析包间隔
tcpdump -i any -w barrier.pcap port 24800

# 3. 使用 Wireshark 分析
# Statistics -> I/O Graph

# 4. 添加内部计时
// 在关键路径添加计时器
class LatencyTimer {
    std::chrono::high_resolution_clock::time_point start;
    const char* name;
public:
    LatencyTimer(const char* n) : name(n), start(std::chrono::high_resolution_clock::now()) {}
    ~LatencyTimer() {
        auto end = std::chrono::high_resolution_clock::now();
        auto us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();
        if (us > 1000) {  // 只记录 > 1ms 的
            LOG((CLOG_WARN "%s took %ld us", name, us));
        }
    }
};
```

---

## 🎯 推荐的优化顺序

| 优先级 | 优化项 | 预期效果 | 实现难度 |
|-------|-------|---------|---------|
| 1 | TCP_NODELAY | 10-50ms 降低 | ✅ 已实现 |
| 2 | Socket 缓冲区 | 5-20ms 降低 | 🟢 简单 |
| 3 | 内存池 | 减少 GC 停顿 | 🟡 中等 |
| 4 | 读写锁 | 提高并发 | 🟡 中等 |
| 5 | 鼠标批处理 | 减少网络包 | 🟡 中等 |
| 6 | 无锁队列 | 减少锁竞争 | 🔴 困难 |
| 7 | 协议压缩 | 减少带宽 | 🔴 困难 |

---

## ⚠️ 注意事项

1. **不要过度优化**：先测量，再优化
2. **保持向后兼容**：协议更改需要客户端和服务器同时更新
3. **平台差异**：某些优化可能只适用于特定平台
4. **测试覆盖**：性能优化可能引入 bug，需要充分测试
