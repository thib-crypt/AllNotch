import SwiftUI
import Defaults
import AppKit

struct CaptureSettingsView: View {
    @Default(.enableScreenshotFeature) var enableScreenshotFeature

    // Capture behavior
    @AppStorage("captureDelaySeconds") var captureDelaySeconds = 0
    @AppStorage("quickCaptureMode") var quickCaptureMode = 1 // 0=save, 1=copy, 2=both, 3=do nothing
    @AppStorage("quickCaptureOpenEditor") var quickCaptureOpenEditor = false
    @AppStorage("playCopySound") var playCopySound = true
    @AppStorage("showCaptureToolbar") var showCaptureToolbar = true

    // Saving (read by SaveDirectoryAccess / ImageEncoder)
    @AppStorage("imageFormat") var imageFormat = "png"
    @AppStorage("imageQuality") var imageQuality = 0.85
    @AppStorage("downscaleRetina") var downscaleRetina = false
    @State private var saveDirDisplay = SaveDirectoryAccess.displayPath

    // Vignette (floating thumbnail)
    @AppStorage("showFloatingThumbnail") var showFloatingThumbnail = true
    @AppStorage("thumbnailPlacement") var thumbnailPlacement = 3 // bottomRight
    @AppStorage("thumbnailAutoDismiss") var thumbnailAutoDismiss = 5
    @AppStorage("thumbnailScale") var thumbnailScale = 1.0
    @AppStorage("thumbnailStacking") var thumbnailStacking = true

    // OCR
    @AppStorage("ocrAction") var ocrAction = 0 // 0=both, 1=window only, 2=copy only

    // Cloud upload
    @AppStorage("uploadProvider") var uploadProvider = "imgbb"
    @AppStorage("imgbbAPIKey") var imgbbAPIKey = ""
    @AppStorage("s3Endpoint") var s3Endpoint = ""
    @AppStorage("s3Bucket") var s3Bucket = ""
    @AppStorage("s3AccessKey") var s3AccessKey = ""
    @AppStorage("s3SecretKey") var s3SecretKey = ""
    @AppStorage("s3Region") var s3Region = "us-east-1"
    @AppStorage("s3PublicURL") var s3PublicURL = ""

    @State private var showingS3Secret = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Screen Capture Tab", isOn: $enableScreenshotFeature)
            } header: {
                Text("General")
            } footer: {
                Text("Enable or disable the capture tab in AllNotch. Raccourcis globaux : Cmd+Shift+X pour capturer une zone, Cmd+Shift+F pour plein écran.")
            }

            if enableScreenshotFeature {
                captureBehaviorSection
                savingSection
                vignetteSection
                ocrSection
                cloudSection
            }
        }
        .disableAutocorrection(true)
    }

    // MARK: - Capture Behavior

    private var captureBehaviorSection: some View {
        Section {
            Picker("Default Action", selection: $quickCaptureMode) {
                Text("Copy to Clipboard").tag(1)
                Text("Save to Folder").tag(0)
                Text("Both (Copy + Save)").tag(2)
                Text("Do Nothing").tag(3)
            }

            Toggle("Show Capture Tools Overlay", isOn: $showCaptureToolbar)
            Toggle("Open in Editor Immediately", isOn: $quickCaptureOpenEditor)
            Toggle("Play Capture Sound", isOn: $playCopySound)

            Picker("Pre-capture Delay", selection: $captureDelaySeconds) {
                Text("Instant").tag(0)
                Text("3 seconds").tag(3)
                Text("5 seconds").tag(5)
                Text("10 seconds").tag(10)
            }
        } header: {
            Text("Capture Behavior")
        } footer: {
            if quickCaptureOpenEditor {
                Text("Chaque capture ouvre directement l'éditeur (la vignette est ignorée).")
            } else if showCaptureToolbar {
                Text("Après la sélection, la barre d'outils (annotation, copie, enregistrement…) s'affiche. Validez pour obtenir la vignette ; si vous l'ignorez, l'« Default Action » est appliquée. Cliquez la vignette pour éditer.")
            } else {
                Text("La barre d'outils est masquée : sélectionnez une zone et la vignette apparaît directement. Si vous l'ignorez, l'« Default Action » est appliquée. Cliquez la vignette pour éditer.")
            }
        }
    }

    // MARK: - Saving

    private var savingSection: some View {
        Section {
            HStack {
                Text("Save Folder")
                Spacer()
                Text(saveDirDisplay)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choisir…") { chooseSaveDirectory() }
            }

            Picker("Image Format", selection: $imageFormat) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpeg")
                Text("HEIC").tag("heic")
                Text("WebP").tag("webp")
            }

            if imageFormat != "png" {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Quality")
                        Spacer()
                        Text("\(Int(imageQuality * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $imageQuality, in: 0.1...1.0, step: 0.05)
                }
            }

            Toggle("Downscale Retina (2x → 1x)", isOn: $downscaleRetina)
        } header: {
            Text("Saving")
        } footer: {
            Text("Le dossier et le format s'appliquent à l'enregistrement automatique (Default Action) comme au bouton « Save » de la vignette.")
        }
    }

    // MARK: - Vignette

    private var vignetteSection: some View {
        Section {
            Toggle("Show Floating Vignette (Thumbnail)", isOn: $showFloatingThumbnail)

            if showFloatingThumbnail {
                Picker("Vignette Corner", selection: $thumbnailPlacement) {
                    Text("Top Left").tag(0)
                    Text("Top Right").tag(1)
                    Text("Bottom Left").tag(2)
                    Text("Bottom Right").tag(3)
                }

                Picker("Auto-dismiss Delay", selection: $thumbnailAutoDismiss) {
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("Never").tag(0)
                }

                Picker("Vignette Size", selection: $thumbnailScale) {
                    Text("Small").tag(0.75)
                    Text("Medium").tag(1.0)
                    Text("Large").tag(1.35)
                }

                Toggle("Stack Multiple Vignettes", isOn: $thumbnailStacking)
            }
        } header: {
            Text("Vignette")
        } footer: {
            if thumbnailAutoDismiss == 0 {
                Text("« Never » : la vignette reste affichée jusqu'à une action. L'action par défaut différée ne se déclenche donc jamais seule.")
            } else {
                Text("La vignette disparaît après ce délai. C'est à ce moment que l'action par défaut s'applique si vous ne l'avez pas touchée.")
            }
        }
    }

    // MARK: - OCR

    private var ocrSection: some View {
        Section {
            Picker("OCR Result Action", selection: $ocrAction) {
                Text("Copy & Show Window").tag(0)
                Text("Show Window Only").tag(1)
                Text("Copy to Clipboard Only").tag(2)
            }
        } header: {
            Text("Text Recognition (OCR)")
        } footer: {
            Text("Comportement après une capture OCR (Cmd+Shift+O ou bouton OCR).")
        }
    }

    // MARK: - Cloud Upload

    private var cloudSection: some View {
        Section {
            Picker("Upload Destination", selection: $uploadProvider) {
                Text("Imgbb (Anonymous/Free)").tag("imgbb")
                Text("Google Drive").tag("gdrive")
                Text("S3 Compatible Storage").tag("s3")
            }

            if uploadProvider == "imgbb" {
                SecureField("Imgbb API Key", text: $imgbbAPIKey)
                    .textFieldStyle(.roundedBorder)
                Text("Get a free API Key on imgbb.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if uploadProvider == "s3" {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Endpoint URL (ex: https://s3.amazonaws.com)", text: $s3Endpoint)
                        .textFieldStyle(.roundedBorder)
                    TextField("Bucket Name", text: $s3Bucket)
                        .textFieldStyle(.roundedBorder)
                    TextField("Access Key ID", text: $s3AccessKey)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        if showingS3Secret {
                            TextField("Secret Access Key", text: $s3SecretKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Secret Access Key", text: $s3SecretKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(showingS3Secret ? "Hide" : "Show") {
                            showingS3Secret.toggle()
                        }
                    }

                    TextField("Region", text: $s3Region)
                        .textFieldStyle(.roundedBorder)
                    TextField("Custom Public URL prefix (Optional)", text: $s3PublicURL)
                        .textFieldStyle(.roundedBorder)
                }
            } else if uploadProvider == "gdrive" {
                Text("Sign in via the Floating Thumbnail's Upload action to authorize Google Drive access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Cloud Upload")
        } footer: {
            Text("Les images partagées vers le Cloud génèrent un lien court copié instantanément dans votre presse-papiers.")
        }
    }

    // MARK: - Actions

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.directoryURL = SaveDirectoryAccess.directoryHint()
        if panel.runModal() == .OK, let url = panel.url {
            SaveDirectoryAccess.save(url: url)
            saveDirDisplay = SaveDirectoryAccess.displayPath
        }
    }
}
