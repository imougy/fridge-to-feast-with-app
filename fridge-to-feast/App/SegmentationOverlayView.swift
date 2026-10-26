import SwiftUI
import FridgeToFeastCore

/// Draws SAM 3.1's segments over the photo that produced them, each box
/// labeled. This is the demo's first wow moment (brief: "See"), so it is
/// deliberately simple and robust: boxes + labels, no gestures to break.
struct SegmentationOverlayView: View {
    let photo: CapturedPhoto
    let items: [SegmentedItem]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let image = UIImage(data: photo.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width * 0.75)
                        .clipped()
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                }
                ForEach(items) { item in
                    let rect = CGRect(
                        x: item.box.x * geo.size.width,
                        y: item.box.y * geo.size.width * 0.75,
                        width: item.box.width * geo.size.width,
                        height: item.box.height * geo.size.width * 0.75
                    )
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                        Text(item.rawLabel)
                            .font(.caption2.bold())
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.yellow)
                            .foregroundStyle(.black)
                    }
                    .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .frame(height: 240)
    }
}
