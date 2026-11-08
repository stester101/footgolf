"""Focused private-room protocol checks; no external service required."""
import asyncio
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve

spec = importlib.util.spec_from_file_location('footgolf_relay', Path(__file__).resolve().parents[2] / 'relay/server.py')
relay = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = relay
spec.loader.exec_module(relay)

class RelayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        relay.ROOMS.clear()
        self.server = await serve(relay.handler, '127.0.0.1', 0)
        self.url = f'ws://127.0.0.1:{self.server.sockets[0].getsockname()[1]}'
        self.peers = []

    async def asyncTearDown(self):
        for peer in self.peers:
            await peer.close()
        self.server.close()
        await self.server.wait_closed()
        relay.ROOMS.clear()

    async def receive(self, ws, kind):
        async with asyncio.timeout(3):
            while True:
                msg = json.loads(await ws.recv())
                if msg['type'] == kind:
                    return msg

    async def send(self, ws, **data):
        await ws.send(json.dumps(data))

    async def new(self, kind, **kwargs):
        ws = await connect(self.url, proxy=None)
        self.peers.append(ws)
        await self.send(ws, type=kind, protocol=1, name='Test', fingerprint='a'*64, **kwargs)
        return ws

    async def test_capacity_readiness_authority_and_reconnect(self):
        host = await self.new('host')
        welcome = await self.receive(host, 'welcome')
        code = welcome['code']
        await self.send(host, type='start', setup={})
        self.assertIn('ready', (await self.receive(host, 'error'))['message'])
        players, tokens = [host], [welcome['token']]
        for i in range(1, 4):
            guest = await self.new('join', code=code)
            reply = await self.receive(guest, 'welcome')
            self.assertEqual(reply['seat'], i)
            players.append(guest)
            tokens.append(reply['token'])
        fifth = await self.new('join', code=code)
        self.assertIn('full', (await self.receive(fifth, 'error'))['message'])
        for player in players:
            await self.send(player, type='ready', ready=True)
        while not all(p.ready for p in relay.ROOMS[code].peers):
            await asyncio.sleep(.01)
        await self.send(host, type='start', setup={'course': 'starter'})
        for player in players:
            await self.receive(player, 'start')
        await self.send(players[1], type='event', event={'kind': 'forged'})
        await self.receive(players[1], 'error')
        await self.send(players[1], type='intent', seat=0, command={'action': 'shot'})
        self.assertEqual((await self.receive(host, 'intent'))['seat'], 1)
        await players[1].close()
        while relay.ROOMS[code].peers[1].socket is not None:
            await asyncio.sleep(.01)
        await self.send(host, type='intent', command={'action': 'shot'})
        self.assertIn('reconnection', (await self.receive(host, 'error'))['message'])
        resumed = await self.new('resume', code=code, token=tokens[1])
        self.assertEqual((await self.receive(resumed, 'welcome'))['seat'], 1)
        self.assertEqual((await self.receive(host, 'resync'))['seat'], 1)
        await self.send(host, type='leave')
        await self.receive(resumed, 'ended')
        self.assertNotIn(code, relay.ROOMS)

    async def test_mismatched_build_and_malformed_messages(self):
        host = await self.new('host')
        code = (await self.receive(host, 'welcome'))['code']
        guest = await connect(self.url, proxy=None)
        self.peers.append(guest)
        await guest.send('[]')
        await self.receive(guest, 'error')
        await self.send(guest, type='join', protocol=1, name='Guest', fingerprint='b'*64, code=code)
        self.assertIn('differ', (await self.receive(guest, 'error'))['message'])
        self.assertEqual(len(relay.ROOMS[code].peers), 1)

if __name__ == '__main__':
    unittest.main()
