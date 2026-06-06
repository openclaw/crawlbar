import CrawlBarCore
import Foundation

@main
enum CrawlBarSelfTest {
    static func main() throws {
        try Self.testAppIDSortsByRawValue()
        try Self.testDefaultConfigNormalizesBuiltInApps()
        try Self.testConfigStoreRoundTrips()
        try Self.testExternalManifestCatalog()
        try Self.testNativeConfigRoundTrips()
        try Self.testStatusSecretsLoadFromNativeConfig()
        try Self.testStatusMapperNormalizesCounts()
        try Self.testStatusMapperTrustsCrawlerState()
        try Self.testStatusMapperNormalizesWacliDoctorOutput()
        try Self.testStatusMapperNormalizesGogAuthStatus()
        try Self.testStatusMapperNormalizesBirdclawAuthStatus()
        try Self.testGogStatusServiceVerifiesOAuthOrServiceAccount()
        try Self.testActionFailuresPreserveStatusMetadata()
        try Self.testActionLogStoreReadsRecentResults()
        try Self.testQueryActionResolverSkipsSQLForPlainText()
        try Self.testExecutableResolverUsesMacCliFallbackPaths()
        try Self.testRegistryResolvesBirdclawAccessPathBinary()
        try Self.testConfigValuesReachCommandEnvironment()
        try Self.testRemoteSshExecutionBuildsCommand()
        try Self.testWacliSearchJoinsQueryArguments()
        try Self.testGitcrawlCommandArgumentsInferRepository()
        try Self.testCommandTimeoutEscalates()
        try Self.testDatabaseBackupCopiesFiles()
        try Self.testRedactorScrubsSecrets()
        print("crawlbar selftest ok")
    }
}
