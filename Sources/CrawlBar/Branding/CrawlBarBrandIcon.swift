import CrawlBarCore
import SwiftUI

struct CrawlBarBrandIcon: View {
    let manifest: CrawlAppManifest?
    let appID: CrawlAppID

    var body: some View {
        Image(nsImage: CrawlBarIconFactory.image(
            for: self.appID,
            manifest: self.manifest,
            size: 64))
        .resizable()
        .interpolation(.high)
        .aspectRatio(1, contentMode: .fit)
    }
}
