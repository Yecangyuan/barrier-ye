# Barrier 更多优化点详细分析

## 🔴 高优先级优化

### 1. Timer 性能优化（显著热点）

**问题代码** (`src/lib/base/EventQueue.cpp:519-522`):
```cpp
// countdown elapsed time
for (TimerQueue::iterator index = m_timerQueue.begin();
                        index != m_timerQueue.end(); ++index) {
    (*index) -= time;
}
```

**问题**: 每次检查 timer 都要遍历所有 timer，复杂度 O(n)

**优化方案** - 使用更高效的 Timer 算法:
```cpp
class OptimizedTimerQueue {
private:
    // 使用最小堆 + 批量时间偏移
    struct TimerEntry {
        double deadline;  // 绝对截止时间，不是相对时间
        Timer* timer;
        bool operator>(const TimerEntry& other) const {
            return deadline > other.deadline;
        }
    };
    
    std::priority_queue<TimerEntry, std::vector<TimerEntry>, std::greater<>> timers;
    double baseTime = 0.0;  // 基准时间偏移
    
public:
    void addTimer(double timeout, Timer* timer) {
        TimerEntry entry;
        entry.deadline = baseTime + timeout;
        entry.timer = timer;
        timers.push(entry);
    }
    
    // O(1) 检查过期，无需遍历所有 timer
    bool hasExpired(double currentTime) {
        baseTime = currentTime;  // 只更新基准时间
        if (timers.empty()) return false;
        return timers.top().deadline <= currentTime;
    }
};
```

**预期收益**:
- 检查过期: O(n) → O(1)
- 大量 timer 时显著减少 CPU 使用
- **预估性能提升**: 5-15%

---

### 2. 日志系统优化（高频调用）

**问题**: 频繁调用 `LOG()` 宏，即使日志级别被过滤也会进行字符串格式化

**优化方案** - 延迟格式化:
```cpp
// 当前代码（每次都格式化）
LOG((CLOG_DEBUG "mouse moved to %d, %d", x, y));

// 优化方案（仅在需要时格式化）
#define LOG_IF(level, expr) \
    do { if (CLOG->getFilter() >= level) { LOG(expr); } } while(0)

// 或者使用宏延迟参数计算
#define LAZY_LOG(level, ...) \
    do { if (shouldLog(level)) log(__VA_ARGS__); } while(0)

// 更好的方案：编译期消除
#ifdef NDEBUG
    #define LOG_DEBUG(...) ((void)0)
#else
    #define LOG_DEBUG(...) LOG((CLOG_DEBUG __VA_ARGS__))
#endif
```

**预期收益**:
- 减少不必要的字符串格式化
- 减少系统调用
- **预估性能提升**: 3-10% (取决于日志级别)

---

### 3. 哈希表替换（std::map → unordered_map）

**问题代码** (`src/lib/base/EventQueue.h`):
```cpp
typedef std::map<Event::Type, const char*> TypeMap;
typedef std::map<std::string, Event::Type> NameMap;
typedef std::map<Event::Type, IEventJob*> TypeHandlerTable;
typedef std::map<void*, TypeHandlerTable> HandlerTable;
```

**问题**: std::map 是红黑树，查找 O(log n)；unordered_map 是哈希表，查找 O(1)

**优化方案**:
```cpp
// 替换为 unordered_map
typedef std::unordered_map<Event::Type, const char*> TypeMap;
typedef std::unordered_map<std::string, Event::Type> NameMap;
typedef std::unordered_map<Event::Type, IEventJob*> TypeHandlerTable;
typedef std::unordered_map<void*, TypeHandlerTable> HandlerTable;

// 对于 void* 键，需要自定义哈希（如果默认不够好）
struct PtrHash {
    size_t operator()(const void* ptr) const {
        return std::hash<uintptr_t>()(reinterpret_cast<uintptr_t>(ptr));
    }
};
```

**预期收益**:
- 查找速度: O(log n) → O(1)
- 更少的缓存未命中
- **预估性能提升**: 2-5%

---

### 4. Event 内存池优化

**问题代码** (`src/lib/base/EventQueue.cpp:465-502`):
```cpp
// 频繁的 vector 操作和 Event 拷贝
UInt32 EventQueue::saveEvent(const Event& event) {
    if (!m_oldEventIDs.empty()) {
        const UInt32 id = m_oldEventIDs.back();
        m_oldEventIDs.pop_back();
        m_events[id] = event;  // Event 拷贝
        return id;
    }
    const UInt32 id = static_cast<UInt32>(m_events.size());
    m_events.push_back(event);  // 可能触发 vector 重新分配
    return id;
}
```

**优化方案**:
```cpp
class EventPool {
private:
    static constexpr size_t POOL_SIZE = 4096;
    static constexpr size_t MAX_FREE = 1024;
    
    struct EventSlot {
        Event event;
        bool used = false;
    };
    
    std::vector<EventSlot> pool;
    std::vector<uint32_t> freeList;
    uint32_t nextSlot = 0;
    
public:
    EventPool() : pool(POOL_SIZE) {}
    
    uint32_t acquire(const Event& event) {
        uint32_t id;
        if (!freeList.empty()) {
            id = freeList.back();
            freeList.pop_back();
        } else if (nextSlot < POOL_SIZE) {
            id = nextSlot++;
        } else {
            // 扩容（很少发生）
            id = pool.size();
            pool.emplace_back();
        }
        pool[id].event = event;
        pool[id].used = true;
        return id;
    }
    
    void release(uint32_t id) {
        if (id < pool.size() && pool[id].used) {
            pool[id].used = false;
            if (freeList.size() < MAX_FREE) {
                freeList.push_back(id);
            }
        }
    }
    
    Event* get(uint32_t id) {
        if (id < pool.size() && pool[id].used) {
            return &pool[id].event;
        }
        return nullptr;
    }
};
```

**预期收益**:
- 消除频繁的内存分配
- 更好的缓存局部性
- **预估性能提升**: 5-15%

---

## 🟡 中优先级优化

### 5. 字符串操作优化

**问题**: `src/lib/base/String.cpp` 中的格式化函数使用复杂

**优化方案** - 使用更高效的字符串操作:
```cpp
// 预分配缓冲区避免重复分配
std::string formatString(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    
    // 先获取大小
    va_list args_copy;
    va_copy(args_copy, args);
    int size = vsnprintf(nullptr, 0, fmt, args_copy);
    va_end(args_copy);
    
    if (size < 0) return "";
    
    // 一次性分配
    std::string result;
    result.resize(size);
    vsnprintf(&result[0], size + 1, fmt, args);
    
    va_end(args);
    return result;
}
```

---

### 6. SIMD 优化（高级）

**适用场景**: 鼠标移动数据处理、图像数据处理

**优化方案**:
```cpp
#include <immintrin.h>

// 批量处理鼠标坐标
void processMouseBatch(const int* x, const int* y, int count) {
    int i = 0;
    // 使用 SSE 一次处理 4 个坐标
    for (; i + 4 <= count; i += 4) {
        __m128i vx = _mm_loadu_si128((__m128i*)&x[i]);
        __m128i vy = _mm_loadu_si128((__m128i*)&y[i]);
        // 批量处理...
    }
    // 处理剩余
    for (; i < count; i++) {
        // 单个处理
    }
}
```

**预期收益**:
- 批量数据处理 4x 速度提升
- 需要特定 CPU 支持

---

### 7. 编译器优化选项

**优化方案** - 添加更多编译选项:
```cmake
# CMakeLists.txt 添加
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    # 链接时优化
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
    
    # CPU 特定优化（如果目标机器确定）
    # set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native")
    
    # 更快的数学运算（允许轻微精度损失）
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffast-math")
    
    # 向量化报告
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fopt-info-vec")
    
    # 使用新一点的 C++ 标准
    set(CMAKE_CXX_STANDARD 17)
endif()
```

---

### 8. 预取优化

**适用场景**: 网络缓冲区、事件队列

**优化方案**:
```cpp
#include <xmmintrin.h>  // _mm_prefetch

void processNetworkData(const char* data, size_t len) {
    for (size_t i = 0; i < len; i += 64) {
        // 预取下一个缓存行
        _mm_prefetch(data + i + 64, _MM_HINT_T0);
        
        // 处理当前数据
        processChunk(data + i);
    }
}
```

---

## 🟢 低优先级优化

### 9. 内存对齐

**优化方案**:
```cpp
// 对齐数据结构以提高缓存效率
struct alignas(64) AlignedEvent {  // 缓存行对齐
    Event event;
    // 64 字节对齐避免伪共享
};
```

### 10. 分支预测提示

**优化方案**:
```cpp
#ifdef __GNUC__
    #define likely(x) __builtin_expect(!!(x), 1)
    #define unlikely(x) __builtin_expect(!!(x), 0)
#else
    #define likely(x) (x)
    #define unlikely(x) (x)
#endif

// 使用示例
if (unlikely(m_timerQueue.empty())) {
    return false;
}
```

---

## 📊 优化效果预估汇总

| 优化项 | 复杂度 | 预期提升 | 实施建议 |
|--------|--------|----------|----------|
| Timer 算法优化 | 中 | 5-15% | 🔴 推荐 |
| 日志延迟格式化 | 低 | 3-10% | 🔴 推荐 |
| unordered_map | 低 | 2-5% | 🔴 推荐 |
| Event 内存池 | 中 | 5-15% | 🟡 可选 |
| 字符串预分配 | 低 | 2-3% | 🟡 可选 |
| SIMD 优化 | 高 | 10-30%* | 🟢 特定场景 |
| 编译器选项 | 低 | 5-10% | 🔴 推荐 |
| 预取优化 | 中 | 2-5% | 🟢 可选 |

*SIMD 优化仅在特定场景下有效

**总预期提升**: 20-50%（取决于应用场景）

---

## 🛠️ 实施优先级建议

### 第一阶段（快速收益）
1. ✅ 添加编译器优化选项
2. ✅ 日志宏优化（NDEBUG 模式）
3. ✅ std::map → unordered_map

### 第二阶段（中等收益）
4. Timer 算法重构
5. Event 内存池

### 第三阶段（高级优化）
6. SIMD 优化（如果需要）
7. 预取优化

---

## 📈 如何验证优化效果

```cpp
// 在代码中添加测量点
class ScopedTimer {
    const char* name;
    std::chrono::high_resolution_clock::time_point start;
public:
    ScopedTimer(const char* n) : name(n), start(std::chrono::high_resolution_clock::now()) {}
    ~ScopedTimer() {
        auto us = std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::high_resolution_clock::now() - start).count();
        if (us > 100) {  // 只记录慢的操作
            std::cerr << name << ": " << us << " us\n";
        }
    }
};

// 使用
void hotFunction() {
    ScopedTimer timer("hotFunction");
    // ... 代码
}
```

使用 perf 工具：
```bash
# Linux
perf record -g ./barriers
perf report

# macOS
instruments -t "Time Profiler" ./barriers
```
