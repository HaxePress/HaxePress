package hx.press.config;

import hx.well.config.IConfig;
#if !cms_plugin
#if php
import hx.press.provider.PhpLogProvider;
#end
import hx.press.provider.BootProvider;
import hx.press.provider.DatabaseProvider;
import hx.press.provider.ResponseEncodingProvider;
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
            #if php
            PhpLogProvider,
            #end
            #if cms_tests
            TestProvider,
            #end
            ResponseEncodingProvider,
            DatabaseProvider,
            BootProvider
        ];
        #end
    }
}
