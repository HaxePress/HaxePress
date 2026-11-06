# HaxePress GitHub Release Example

This example targets HaxePress 2.16.0 and plugin API 4. Activating it adds the `/github-release-example` JSON endpoint. Deactivating it unregisters the route.

## Install

1. Sign in to a HaxePress JVM site with package management access.
2. Open **Plugins** and select **Install from GitHub**.
3. Paste the repository URL `https://github.com/hxwell/haxepress-plugin-example` and choose **Load releases**.
4. Select the ZIP under `v0.1.1`, inspect it and choose **Install package**.
5. Activate **GitHub Release Example**, then open `/github-release-example` on the site.

## Build and release

Run the following from the example repository root using the HaxePress build prerequisites. The pinned checkout matches the version in `cms-package.json`.

```sh
git clone https://github.com/hxwell/haxepress.git .build/haxepress
git -C .build/haxepress checkout 7b27130020115d2b8a37477a623aa81cd2c772fe
mkdir -p .build/haxepress/examples/plugins/github-release-example
cp -R cms-package.json src .build/haxepress/examples/plugins/github-release-example/
make -C .build/haxepress setup
make -C .build/haxepress build
```

The build creates `.build/haxepress/Export/packages/github-release-example-0.1.1.zip` with the JVM JAR, CPPIA and PHP modules. Attach this ZIP to a published GitHub release in your public repository.

```sh
gh release create v0.1.1 \
  .build/haxepress/Export/packages/github-release-example-0.1.1.zip \
  --title v0.1.1 --generate-notes
```

Use the same layout to start your own plugin repository. Update the slug, entrypoint and package version in `cms-package.json`. Build each release against the exact HaxePress version declared by its manifest.

Generate a UUID once for your plugin project and place it in `pluginId`. Keep that value on subsequent releases so installations and scheduled jobs continue to refer to the same plugin.
