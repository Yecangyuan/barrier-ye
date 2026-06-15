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

#include "test/global/TestEventQueue.h"

#include "arch/Arch.h"
#include "test/global/gtest.h"

TEST(EventQueueTests, timersInDifferentQueues_doNotShareElapsedTime)
{
    TestEventQueue first;
    TestEventQueue second;

    EventQueueTimer* firstTimer = first.newTimer(0.2, NULL);
    EventQueueTimer* secondTimer = second.newTimer(0.2, NULL);

    ARCH->sleep(0.11);

    Event event;
    EXPECT_FALSE(first.getEvent(event, 0.0));
    EXPECT_FALSE(second.getEvent(event, 0.0));

    first.deleteTimer(firstTimer);
    second.deleteTimer(secondTimer);
}

TEST(EventQueueTests, deletedTimer_doesNotGenerateEvent)
{
    TestEventQueue queue;
    EventQueueTimer* timer = queue.newTimer(0.01, NULL);

    queue.deleteTimer(timer);
    ARCH->sleep(0.02);

    Event event;
    EXPECT_FALSE(queue.getEvent(event, 0.0));
}
