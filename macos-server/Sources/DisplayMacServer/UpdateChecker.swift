import Foundation
import AppKit

public struct AppUpdateInfo {
    public let latestVersion: String
    public let downloadURL: String
    public let releaseNotes: String
}

public final class UpdateChecker {
    public static let shared = UpdateChecker()
    public static let currentVersion = "1.1.0"
    public static let repoOwner = "sumitkumar"
    public static let repoName = "DisplayMac"

    private init() {}

    public func checkForUpdates(completion: @escaping (AppUpdateInfo?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("DisplayMac-Updater", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                completion(nil)
                return
            }

            let releaseVersion = tagName.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if releaseVersion.compare(Self.currentVersion, options: .numeric) == .orderedDescending {
                let htmlUrl = json["html_url"] as? String ?? "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases"
                let body = json["body"] as? String ?? "A new version of DisplayMac is available!"
                let info = AppUpdateInfo(latestVersion: releaseVersion, downloadURL: htmlUrl, releaseNotes: body)
                DispatchQueue.main.async {
                    completion(info)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }.resume()
    }
}
