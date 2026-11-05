package hx.press.config;

import hx.well.config.IConfig;
#if !cms_plugin
import hx.press.provider.BootProvider;
import hx.press.provider.DatabaseProvider;
#end
import hx.well.provider.AbstractProvider;
#if cms_tests
import fixtures.TestProvider;
#end

class ProviderConfig implements IConfig {
    public function new() {}

    public function get():Array<Class<AbstractProvider>> {
        #if cms_plugin
        return [];
        #else
        return [
            #if cms_tests
            TestProvider,
            #end
            DatabaseProvider,
            BootProvider
        ];
        #end
    }
}
