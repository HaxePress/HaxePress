package hx.press.provider;

import hx.press.i18n.TranslationSync;
import hx.well.provider.AbstractProvider;
import hx.press.database.InitialSchema;
import hx.press.database.MigrationState;
import hx.press.install.InstallationEnv;
import hx.press.install.InstallationState;
import hx.press.SiteSettingsStore;
import hx.press.database.ManagedContentImages;
import hx.press.database.ManagedCategories;
import hx.press.database.QueryMetadata;
import hx.press.database.CmsSchema;
import hx.press.database.ContentStructureSchema;
import hx.press.database.AccessSchema;
import hx.press.database.GeneralNamesMigration;
import hx.press.database.SiteIdentityMigration;
import hx.press.packages.PackageBundles;
import hx.well.database.Connection;
import hx.press.MediaCatalog;
import hx.press.NavigationData;
import hx.press.navigation.NavigationRegions;
import hx.press.database.ThemeDesignSchema;
import hx.press.database.ThemeAiSchema;
import hx.press.database.AdminMcpSchema;
import hx.press.database.AdminPreferenceSchema;
import hx.press.database.LanguageSchema;
import hx.press.database.TranslationSchema;
import hx.press.database.ThemeAssetSchema;

class DatabaseProvider extends AbstractProvider {
    public function boot():Void {
        InstallationState.initialize();
        if (InstallationState.pending) {
            return;
        }
        MigrationState.ensure(migrate);
        try {
            InstallationEnv.forgetAdministrator();
        } catch (error:Dynamic) {
            trace('The administrator settings could not be cleared from .env: ${Std.string(error)}');
        }
    }

    public static function migrate():Void {
        GeneralNamesMigration.prepareSchema();
        InitialSchema.up();
        CmsSchema.up();
        GeneralNamesMigration.up();
        SiteIdentityMigration.up();
        AccessSchema.up();
        ContentStructureSchema.up();
        ThemeDesignSchema.up();
        ThemeAiSchema.up();
        AdminMcpSchema.up();
        ThemeAssetSchema.up();
        AdminPreferenceSchema.up();
        LanguageSchema.up();
        TranslationSchema.up();
        NavigationRegions.initialize();
        SiteSettingsStore.initialize();
        ManagedCategories.run();
        ManagedContentImages.run();
        QueryMetadata.run();
        PackageBundles.ensure();
        TranslationSync.core();
        MediaCatalog.importExisting();
        NavigationData.ensure();
        Connection.free();
    }
}
