"""A plain HTTP proxy (CONNECT and absolute-URI requests) on loopback that
logs each target, so a test can tell traffic went through it.

Usage: python -I coexist_upstream.py <log file> <port>
"""

import asyncio
import sys
from urllib.parse import urlsplit

LOG, PORT = sys.argv[1], int(sys.argv[2])


async def pipe(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, OSError):
        pass
    finally:
        writer.close()


async def handle(reader, writer):
    try:
        method, target, _ = (await reader.readline()).decode('latin-1').split(' ', 2)
        headers = []
        while (line := await reader.readline()) not in (b'\r\n', b'\n', b''):
            headers.append(line)
        if method == 'CONNECT':
            host, port = target.rsplit(':', 1)
            up_reader, up_writer = await asyncio.open_connection(host.strip('[]'), int(port))
            writer.write(b'HTTP/1.1 200 Connection established\r\n\r\n')
            await writer.drain()
        else:
            url = urlsplit(target)
            host, port = url.hostname, url.port or 80
            up_reader, up_writer = await asyncio.open_connection(host, port)
            path = (url.path or '/') + (f'?{url.query}' if url.query else '')
            kept = [h for h in headers if not h.lower().startswith(b'proxy-')]
            up_writer.write(f'{method} {path} HTTP/1.1\r\n'.encode() + b''.join(kept) + b'\r\n')
        with open(LOG, 'a', encoding='utf-8') as log:
            log.write(f'{method} {host}:{port}\n')
        await asyncio.gather(pipe(reader, up_writer), pipe(up_reader, writer))
    except (ConnectionError, OSError, ValueError):
        writer.close()


async def main():
    server = await asyncio.start_server(handle, '127.0.0.1', PORT)
    async with server:
        await server.serve_forever()


asyncio.run(main())
