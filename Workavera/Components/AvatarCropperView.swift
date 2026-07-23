import SwiftUI
import UIKit

/// A square avatar editor with drag, pinch-to-zoom, and slider controls.
struct AvatarCropperView: View {
    @Environment(\.dismiss) private var dismiss

    private let image: UIImage
    private let onCancel: () -> Void
    private let onCrop: (UIImage) -> Void

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    @State private var cropSide: CGFloat = 0

    private let maximumZoom: CGFloat = 5

    init(
        image: UIImage,
        onCancel: @escaping () -> Void,
        onCrop: @escaping (UIImage) -> Void
    ) {
        self.image = image.normalizedForCropping()
        self.onCancel = onCancel
        self.onCrop = onCrop
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let side = min(proxy.size.width - 32, proxy.size.height * 0.58, 420)

                VStack(spacing: 24) {
                    Spacer(minLength: 20)

                    cropCanvas(side: side)
                        .onAppear {
                            cropSide = side
                        }
                        .onChange(of: side) {
                            cropSide = side
                            constrainCurrentOffset(for: side)
                        }

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Slider(
                                value: Binding(
                                    get: { zoom },
                                    set: { updateZoom($0, cropSide: side) }
                                ),
                                in: 1...maximumZoom
                            )
                            .accessibilityLabel("Photo size")

                            Image(systemName: "photo.fill")
                                .foregroundStyle(.secondary)
                        }

                        Text("Drag to reposition. Pinch or use the slider to resize.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    Button("Reset") {
                        resetCrop()
                    }
                    .font(.subheadline)

                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose") {
                        crop()
                    }
                    .fontWeight(.semibold)
                    .disabled(cropSide <= 0)
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private func cropCanvas(side: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .scaleEffect(zoom)
            .offset(offset)
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(cropSide: side))
            .simultaneousGesture(zoomGesture(cropSide: side))
            .onTapGesture(count: 2) {
                resetCrop()
            }
            .frame(width: side, height: side)
            .clipped()
            .overlay {
                Rectangle()
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .allowsHitTesting(false)
            }
            .background(Color.black)
            .accessibilityLabel("Avatar crop area")
            .accessibilityHint("Drag to reposition the photo and pinch to resize it")
    }

    private func dragGesture(cropSide: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height
                )
                offset = constrained(proposed, zoom: zoom, cropSide: cropSide)
            }
            .onEnded { _ in
                settledOffset = offset
            }
    }

    private func zoomGesture(cropSide: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(max(settledZoom * value, 1), maximumZoom)
                offset = constrained(offset, zoom: zoom, cropSide: cropSide)
            }
            .onEnded { _ in
                settledZoom = zoom
                settledOffset = offset
            }
    }

    private func updateZoom(_ value: CGFloat, cropSide: CGFloat) {
        zoom = min(max(value, 1), maximumZoom)
        offset = constrained(offset, zoom: zoom, cropSide: cropSide)
        settledZoom = zoom
        settledOffset = offset
    }

    private func constrainCurrentOffset(for cropSide: CGFloat) {
        offset = constrained(offset, zoom: zoom, cropSide: cropSide)
        settledOffset = offset
    }

    private func constrained(_ proposed: CGSize, zoom: CGFloat, cropSide: CGFloat) -> CGSize {
        guard cropSide > 0, image.size.width > 0, image.size.height > 0 else {
            return .zero
        }

        let aspectRatio = image.size.width / image.size.height
        let baseWidth = aspectRatio >= 1 ? cropSide * aspectRatio : cropSide
        let baseHeight = aspectRatio >= 1 ? cropSide : cropSide / aspectRatio
        let maximumX = max(0, (baseWidth * zoom - cropSide) / 2)
        let maximumY = max(0, (baseHeight * zoom - cropSide) / 2)

        return CGSize(
            width: min(max(proposed.width, -maximumX), maximumX),
            height: min(max(proposed.height, -maximumY), maximumY)
        )
    }

    private func resetCrop() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoom = 1
            settledZoom = 1
            offset = .zero
            settledOffset = .zero
        }
    }

    private func crop() {
        guard let cropped = image.squareCrop(
            zoom: zoom,
            offset: offset,
            cropSide: cropSide
        ) else {
            return
        }
        onCrop(cropped)
        dismiss()
    }
}

private extension UIImage {
    func normalizedForCropping() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func squareCrop(zoom: CGFloat, offset: CGSize, cropSide: CGFloat) -> UIImage? {
        guard let cgImage, cropSide > 0 else { return nil }

        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let pointsPerPixel = max(cropSide / pixelWidth, cropSide / pixelHeight)
        let effectiveScale = pointsPerPixel * zoom
        let displayedWidth = pixelWidth * effectiveScale
        let displayedHeight = pixelHeight * effectiveScale
        let imageOrigin = CGPoint(
            x: (cropSide - displayedWidth) / 2 + offset.width,
            y: (cropSide - displayedHeight) / 2 + offset.height
        )
        let sourceSide = cropSide / effectiveScale

        let sourceX = -imageOrigin.x / effectiveScale
        let sourceY = -imageOrigin.y / effectiveScale
        let pixelSide = max(1, min(floor(sourceSide), pixelWidth, pixelHeight))
        let sourceRect = CGRect(
            x: min(max(round(sourceX), 0), pixelWidth - pixelSide),
            y: min(max(round(sourceY), 0), pixelHeight - pixelSide),
            width: pixelSide,
            height: pixelSide
        )

        guard sourceRect.width > 0,
              sourceRect.height > 0,
              let cropped = cgImage.cropping(to: sourceRect)
        else {
            return nil
        }

        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }
}
