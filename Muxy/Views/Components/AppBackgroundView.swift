import SwiftUI

struct AppBackgroundView: View {
    @Environment(AppBackgroundService.self) private var backgroundService
    @Environment(GhosttyService.self) private var ghostty

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: ghostty.backgroundColor)

                if backgroundService.hasVisibleBackground,
                   let image = backgroundService.currentImage
                {
                    imageView(image, in: geometry.size)
                        .opacity(backgroundService.imageOpacity)
                        .blur(radius: backgroundService.blurRadius)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func imageView(_ image: NSImage, in size: CGSize) -> some View {
        if backgroundService.repeatImage {
            tiledImage(image)
        } else {
            positionedImage(image, in: size)
        }
    }

    private func tiledImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable(resizingMode: .tile)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: backgroundService.position.alignment)
    }

    @ViewBuilder
    private func positionedImage(_ image: NSImage, in size: CGSize) -> some View {
        let view = Image(nsImage: image).interpolation(.high)
        switch backgroundService.fit {
        case .contain:
            view
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height, alignment: backgroundService.position.alignment)
                .modifier(FloatModeModifier(enabled: backgroundService.floatMode))
        case .cover:
            view
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height, alignment: backgroundService.position.alignment)
                .modifier(FloatModeModifier(enabled: false))
                .clipped()
        case .stretch:
            view
                .resizable()
                .frame(width: size.width, height: size.height, alignment: backgroundService.position.alignment)
                .modifier(FloatModeModifier(enabled: false))
        case .none:
            view
                .modifier(FloatModeModifier(enabled: backgroundService.floatMode))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: backgroundService.position.alignment)
        }
    }
}

private struct FloatModeModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        guard enabled else { return AnyView(content) }
        return AnyView(
            content
                .padding(28)
                .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
        )
    }
}
