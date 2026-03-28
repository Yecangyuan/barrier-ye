/*
 * barrier -- mouse and keyboard sharing utility
 * Copyright (C) 2012-2016 Symless Ltd.
 * Copyright (C) 2012 Nick Bolton
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

// uncomment to debug this end of IPC chatter
//#define BARRIER_IPC_VERBOSE

#include "IpcReader.h"
#include <QTcpSocket>
#include "Ipc.h"
#include <QMutex>
#include <QByteArray>

#ifdef BARRIER_IPC_VERBOSE
#include <iostream>
#define IPC_LOG(x) (x)
#else // not defined BARRIER_IPC_VERBOSE
#define IPC_LOG(x)
#endif

IpcReader::IpcReader(QTcpSocket* socket) :
m_Socket(socket)
{
}

IpcReader::~IpcReader()
{
}

void IpcReader::start()
{
    connect(m_Socket, SIGNAL(readyRead()), this, SLOT(read()));
}

void IpcReader::stop()
{
    disconnect(m_Socket, SIGNAL(readyRead()), this, SLOT(read()));
}

void IpcReader::read()
{
    QMutexLocker locker(&m_Mutex);
    IPC_LOG(std::cout << "ready read" << std::endl);

    m_Buffer += m_Socket->readAll();

    while (true) {
        if (m_Buffer.size() < 8) {
            break;
        }

        const char* data = m_Buffer.constData();
        if (memcmp(data, kIpcMsgLogLine, 4) != 0) {
            IPC_LOG(std::cerr << "aborting, message invalid" << std::endl);
            m_Buffer.clear();
            return;
        }

        const int len = bytesToInt(data + 4, 4);
        if (len < 0) {
            IPC_LOG(std::cerr << "aborting, message length invalid" << std::endl);
            m_Buffer.clear();
            return;
        }

        const int messageSize = 8 + len;
        if (m_Buffer.size() < messageSize) {
            break;
        }

        IPC_LOG(std::cout << "reading log line" << std::endl);
        readLogLine(QString::fromUtf8(data + 8, len));
        m_Buffer.remove(0, messageSize);
    }

    IPC_LOG(std::cout << "read done" << std::endl);
}

int IpcReader::bytesToInt(const char *buffer, int size)
{
    if (size == 1) {
        return (unsigned char)buffer[0];
    }
    else if (size == 2) {
        return
            (((unsigned char)buffer[0]) << 8) +
              (unsigned char)buffer[1];
    }
    else if (size == 4) {
        return
            (((unsigned char)buffer[0]) << 24) +
            (((unsigned char)buffer[1]) << 16) +
            (((unsigned char)buffer[2]) << 8) +
              (unsigned char)buffer[3];
    }
    else {
        return 0;
    }
}
