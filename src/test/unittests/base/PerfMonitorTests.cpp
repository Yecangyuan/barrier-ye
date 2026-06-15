/*
 * barrier -- mouse and keyboard sharing utility
 * Copyright (C) 2026 Barrier contributors
 *
 * This package is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * found in the file LICENSE that should have accompanied this file.
 *
 * This package is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "base/PerfMonitor.h"

#include "test/global/gtest.h"

#include <thread>
#include <vector>

TEST(PerfMonitorTests, recordLatency_tracksAverage)
{
    PerfMonitor& monitor = PerfMonitor::instance();
    monitor.reset();

    monitor.recordLatency("operation", 10);
    monitor.recordLatency("operation", 30);

    EXPECT_DOUBLE_EQ(20.0, monitor.getAverageLatency("operation"));
}

TEST(PerfMonitorTests, recordCount_isThreadSafe)
{
    PerfMonitor& monitor = PerfMonitor::instance();
    monitor.reset();

    std::vector<std::thread> threads;
    for (int i = 0; i < 4; ++i) {
        threads.emplace_back([&monitor]() {
            for (int j = 0; j < 1000; ++j) {
                monitor.recordCount("events");
            }
        });
    }

    for (auto& thread : threads) {
        thread.join();
    }

    EXPECT_EQ(4000u, monitor.getCount("events"));
}

TEST(PerfMonitorTests, reset_clearsMetrics)
{
    PerfMonitor& monitor = PerfMonitor::instance();
    monitor.reset();

    monitor.recordLatency("operation", 10);
    monitor.recordCount("events");
    monitor.reset();

    EXPECT_DOUBLE_EQ(0.0, monitor.getAverageLatency("operation"));
    EXPECT_EQ(0u, monitor.getCount("events"));
}
