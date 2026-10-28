import json
import re
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

from app import main


class GreetingTests(unittest.TestCase):
    def test_greeting_default(self):
        self.assertEqual(main.greeting(), "Hello, world!")

    def test_greeting_named(self):
        self.assertEqual(main.greeting("Akin"), "Hello, Akin!")

    def test_version_is_semver(self):
        self.assertRegex(main.VERSION, r"^\d+\.\d+\.\d+$")


class HttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), main.Handler)
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def get(self, path):
        url = f"http://127.0.0.1:{self.port}{path}"
        try:
            with urllib.request.urlopen(url, timeout=3) as resp:
                return resp.status, json.loads(resp.read())
        except urllib.error.HTTPError as err:
            return err.code, json.loads(err.read())

    def test_root(self):
        status, body = self.get("/")
        self.assertEqual(status, 200)
        self.assertEqual(body["message"], "Hello, DevOps!")
        self.assertTrue(re.match(r"^\d+\.\d+\.\d+$", body["version"]))

    def test_healthz(self):
        status, body = self.get("/healthz")
        self.assertEqual(status, 200)
        self.assertEqual(body["status"], "ok")

    def test_unknown_path(self):
        status, _ = self.get("/nope")
        self.assertEqual(status, 404)


if __name__ == "__main__":
    unittest.main()
