using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace GDMENUCardManager.Core
{
    /// <summary>
    /// Fetches the homebrew CDIs published by the dreamcast-homebrew repo so a
    /// save can put the latest builds on the card.
    /// </summary>
    public static class HomebrewSync
    {
        public const string Repo = "richstokes/dreamcast-homebrew";
        public const string ReleaseTag = "continuous";
        private const string ChecksumAssetName = "SHA256SUMS";
        private const string DownloadDirName = "GDMENUCardManager_homebrew";

        private static readonly HttpClient _client;

        static HomebrewSync()
        {
            _client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
            _client.DefaultRequestHeaders.UserAgent.ParseAdd("GDMENUCardManager-Homebrew/1.0");
        }

        /// <summary>
        /// Downloads every CDI from the release into a fresh folder under
        /// tempFolderRoot, checked against the release's SHA256SUMS. Anything
        /// left from an earlier download is removed first, so the files are
        /// always the release's current ones. Returns the local CDI paths.
        /// </summary>
        public static async Task<List<string>> DownloadAsync(string tempFolderRoot, IProgress<string> progress = null,
            CancellationToken cancellationToken = default)
        {
            var downloadDir = Path.Combine(tempFolderRoot, DownloadDirName);
            if (Directory.Exists(downloadDir))
                await Task.Run(() => Directory.Delete(downloadDir, true));
            Directory.CreateDirectory(downloadDir);

            progress?.Report("Looking up the latest homebrew release...");
            var assets = await GetReleaseAssetsAsync(cancellationToken);

            var cdiAssets = assets
                .Where(a => a.Name.EndsWith(".cdi", StringComparison.OrdinalIgnoreCase))
                .ToList();
            if (cdiAssets.Count == 0)
                throw new Exception($"The \"{ReleaseTag}\" release of {Repo} has no CDI files.");

            var checksumAsset = assets.FirstOrDefault(a => a.Name == ChecksumAssetName);
            if (checksumAsset.Url == null)
                throw new Exception($"The \"{ReleaseTag}\" release of {Repo} has no {ChecksumAssetName} file.");

            var checksumText = await _client.GetStringAsync(checksumAsset.Url, cancellationToken);
            var checksums = ParseChecksums(checksumText);

            var paths = new List<string>();
            for (int i = 0; i < cdiAssets.Count; i++)
            {
                var asset = cdiAssets[i];
                progress?.Report($"Downloading homebrew {i + 1} of {cdiAssets.Count}: {asset.Name}");

                if (!checksums.TryGetValue(asset.Name, out var expectedHash))
                    throw new Exception($"{asset.Name} is not listed in {ChecksumAssetName}.");

                var path = Path.Combine(downloadDir, asset.Name);
                using (var response = await _client.GetAsync(asset.Url, HttpCompletionOption.ResponseHeadersRead, cancellationToken))
                {
                    response.EnsureSuccessStatusCode();
                    using (var source = await response.Content.ReadAsStreamAsync(cancellationToken))
                    using (var target = File.Create(path))
                        await source.CopyToAsync(target, cancellationToken);
                }

                var actualHash = await Task.Run(() =>
                {
                    using (var stream = File.OpenRead(path))
                    using (var sha = SHA256.Create())
                        return Convert.ToHexString(sha.ComputeHash(stream));
                });
                if (!actualHash.Equals(expectedHash, StringComparison.OrdinalIgnoreCase))
                    throw new Exception($"{asset.Name} failed its checksum check. Try saving again.");

                paths.Add(path);
            }

            return paths;
        }

        private static async Task<List<(string Name, string Url)>> GetReleaseAssetsAsync(CancellationToken cancellationToken)
        {
            var url = $"https://api.github.com/repos/{Repo}/releases/tags/{ReleaseTag}";
            using (var request = new HttpRequestMessage(HttpMethod.Get, url))
            {
                request.Headers.Accept.ParseAdd("application/vnd.github.v3+json");
                using (var response = await _client.SendAsync(request, cancellationToken))
                {
                    if (!response.IsSuccessStatusCode)
                        throw new Exception($"Could not reach the {Repo} release on GitHub ({(int)response.StatusCode} {response.ReasonPhrase}).");

                    using (var stream = await response.Content.ReadAsStreamAsync(cancellationToken))
                    using (var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken))
                    {
                        return doc.RootElement.GetProperty("assets").EnumerateArray()
                            .Select(a => (a.GetProperty("name").GetString(), a.GetProperty("browser_download_url").GetString()))
                            .ToList();
                    }
                }
            }
        }

        // Lines are "<sha256>  <path>". The paths carry the build folder
        // (dist/name.cdi), so entries are keyed by file name alone.
        private static Dictionary<string, string> ParseChecksums(string text)
        {
            var checksums = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var line in text.Split('\n'))
            {
                var parts = line.Trim().Split(new[] { ' ', '\t' }, 2, StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length == 2)
                    checksums[Path.GetFileName(parts[1].Trim().TrimStart('*'))] = parts[0];
            }
            return checksums;
        }
    }
}
