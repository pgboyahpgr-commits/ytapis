import unittest
from unittest.mock import patch, MagicMock
from ytapis.core import search, get_video, VideoResult, Thumbnail, search_dicts


class TestYtapis(unittest.TestCase):
    def test_video_result_defaults(self):
        vr = VideoResult(id="dQw4w9WgXcQ")
        self.assertEqual(vr.id, "dQw4w9WgXcQ")
        self.assertEqual(vr.title, "Untitled")
        self.assertTrue(vr.full_url.startswith("https://www.youtube.com/watch?v="))
        self.assertTrue(vr.thumbnail.startswith("https://i.ytimg.com/vi/"))
        self.assertFalse(vr.is_live)
        self.assertEqual(vr.duration_seconds, 0)

    def test_video_result_with_values(self):
        vr = VideoResult(
            id="abc",
            title="Test",
            author="Tester",
            thumbnail="https://example.com/thumb.jpg",
            full_url="https://youtube.com/watch?v=abc",
            embed_url="https://youtube.com/embed/abc",
            duration="3:45",
            duration_seconds=225,
            view_count="1.2M views",
            view_count_raw=1200000,
            is_verified=True,
        )
        self.assertEqual(vr.title, "Test")
        self.assertEqual(vr.duration, "3:45")
        self.assertEqual(vr.duration_seconds, 225)
        self.assertTrue(vr.is_verified)

    def test_video_result_to_dict(self):
        vr = VideoResult(id="abc", title="Hello", author="World")
        d = vr.to_dict()
        self.assertEqual(d["id"], "abc")
        self.assertEqual(d["title"], "Hello")
        self.assertIn("thumbnails", d)

    @patch("ytapis.core._fetch")
    def test_get_video_success(self, mock_fetch):
        mock_fetch.return_value = '{"title":"Test Song","author_name":"Artist","thumbnail_url":"https://img.example.com/thumb.jpg"}'
        result = get_video("dQw4w9WgXcQ")
        self.assertEqual(result.title, "Test Song")
        self.assertEqual(result.author, "Artist")

    @patch("ytapis.core._fetch")
    def test_get_video_fallback(self, mock_fetch):
        mock_fetch.side_effect = Exception("connection error")
        result = get_video("dQw4w9WgXcQ")
        self.assertEqual(result.id, "dQw4w9WgXcQ")
        self.assertTrue(len(result.title) > 0)

    @patch("ytapis.core._fetch")
    def test_search(self, mock_fetch):
        yt_initial = {
            "contents": {
                "twoColumnSearchResultsRenderer": {
                    "primaryContents": {
                        "sectionListRenderer": {
                            "contents": [
                                {
                                    "itemSectionRenderer": {
                                        "contents": [
                                            {
                                                "videoRenderer": {
                                                    "videoId": "abc123def45",
                                                    "title": {"runs": [{"text": "Test Video 1"}]},
                                                    "ownerText": {"runs": [{"text": "Channel One"}]},
                                                    "lengthText": {"simpleText": "3:45"},
                                                    "viewCountText": {"simpleText": "1.2M views"},
                                                    "publishedTimeText": {"simpleText": "2 weeks ago"},
                                                    "thumbnail": {"thumbnails": [{"url": "https://i.ytimg.com/vi/abc/hq.jpg", "width": 480, "height": 360}]},
                                                }
                                            },
                                            {
                                                "videoRenderer": {
                                                    "videoId": "xyz987abc12",
                                                    "title": {"runs": [{"text": "Test Video 2"}]},
                                                    "ownerText": {"runs": [{"text": "Channel Two"}]},
                                                    "lengthText": {"simpleText": "10:30"},
                                                    "viewCountText": {"simpleText": "53K views"},
                                                    "publishedTimeText": {"simpleText": "1 month ago"},
                                                    "thumbnail": {"thumbnails": [{"url": "https://i.ytimg.com/vi/xyz/hq.jpg", "width": 480, "height": 360}]},
                                                }
                                            },
                                        ]
                                    }
                                }
                            ]
                        }
                    }
                }
            }
        }
        import json
        html = '<script>var ytInitialData = ' + json.dumps(yt_initial) + ';</script>'
        mock_fetch.return_value = html
        results = search("test", limit=2)
        self.assertEqual(len(results), 2)
        self.assertIsInstance(results[0], VideoResult)
        self.assertEqual(results[0].title, "Test Video 1")
        self.assertEqual(results[0].duration, "3:45")
        self.assertEqual(results[0].duration_seconds, 225)
        self.assertEqual(results[0].view_count_raw, 1200000)
        self.assertEqual(results[1].title, "Test Video 2")
        self.assertEqual(results[1].view_count_raw, 53000)

    def test_search_dicts(self):
        with patch("ytapis.core._fetch") as mock_fetch:
            import json
            yt_initial = {
                "contents": {
                    "twoColumnSearchResultsRenderer": {
                        "primaryContents": {
                            "sectionListRenderer": {
                                "contents": [
                                    {
                                        "itemSectionRenderer": {
                                            "contents": [
                                                {
                                                    "videoRenderer": {
                                                        "videoId": "abc123def45",
                                                        "title": {"runs": [{"text": "Test"}]},
                                                        "ownerText": {"runs": [{"text": "Channel"}]},
                                                        "thumbnail": {"thumbnails": []},
                                                    }
                                                }
                                            ]
                                        }
                                    }
                                ]
                            }
                        }
                    }
                }
            }
            html = '<script>var ytInitialData = ' + json.dumps(yt_initial) + ';</script>'
            mock_fetch.return_value = html
            results = search_dicts("test", limit=1)
            self.assertEqual(len(results), 1)
            self.assertIsInstance(results[0], dict)
            self.assertEqual(results[0]["id"], "abc123def45")

    def test_duration_parsing(self):
        from ytapis.core import _parse_duration
        self.assertEqual(_parse_duration("3:45"), ("3:45", 225))
        self.assertEqual(_parse_duration("1:02:34"), ("1:02:34", 3754))
        self.assertEqual(_parse_duration("0:30"), ("0:30", 30))

    def test_view_count_parsing(self):
        from ytapis.core import _parse_view_count
        self.assertEqual(_parse_view_count("1.2M views"), ("1.2M views", 1200000))
        self.assertEqual(_parse_view_count("53K views"), ("53K views", 53000))
        self.assertEqual(_parse_view_count("1.5B views"), ("1.5B views", 1500000000))


if __name__ == "__main__":
    unittest.main()
