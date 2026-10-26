import SwiftUI
import UIKit

extension PrefKey {
    static let userName = "userName"
    static let profilePhotoVersion = "profilePhotoVersion"
}

/// Stores the profile photo as a small JPEG in the app's private folder.
enum ProfileStore {
    private static var url: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("profile-photo.jpg")
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Shrinks the picked photo to 400 px so it stays small, then saves it.
    static func save(_ data: Data) throws {
        guard let image = UIImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let side: CGFloat = 400
        let scale = side / max(min(image.size.width, image.size.height), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let square = renderer.image { _ in
            image.draw(in: CGRect(
                x: (side - size.width) / 2,
                y: (side - size.height) / 2,
                width: size.width,
                height: size.height
            ))
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try jpeg.write(to: url, options: .atomic)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Round profile picture, or the first letter of the name on a pastel circle.
struct AvatarView: View {
    var size: CGFloat = 48

    @AppStorage(PrefKey.userName) private var userName = "Marshal"
    @AppStorage(PrefKey.profilePhotoVersion) private var photoVersion = 0

    var body: some View {
        // Reading photoVersion makes the view refresh whenever the photo changes.
        let image = photoVersion >= 0 ? ProfileStore.load() : nil

        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(userName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(Pastel.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Pastel.peach)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Pastel.surface, lineWidth: 2.5))
        .accessibilityLabel("Profile picture")
    }
}
