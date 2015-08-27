# Changelog

## 2015-08-26

* **App Deployment:** Support for adding apt packages. Simply add a ``apt-packages`` file to your app that contains the required packages. ([Additional info](https://github.com/experimental-platform/platform-configure-script/wiki/Create-an-app-that-requires-apt-packages))
* **App List:** Dockerfile apps now always show ``none`` as app type (previously they showed a random/wrong app type, fixes [#4](https://github.com/experimental-platform/platform-configure-script/issues/4))
* **System:** Ensure that avahi (bonjour) and samba always come up after boot (fixes [#27](https://github.com/experimental-platform/platform-configure-script/issues/27))
* **System:** Fix compatibility between Dokku and new CoreOS update
* **Updates:** A loading indicator is now shown while checking for new updates

### Breaking changes:

* All apps are now started after boot (previously you had to start them manually, see [#3](https://github.com/experimental-platform/platform-configure-script/issues/3))

## 2015-08-13

* **Testing:** Hooray! We now have a CI based on [CircleCI](https://circleci.com/). Most repositories already have their tests running there. A status icon in the README shows the current test status. 
* **App Deployment:** "Waiting for your app to be deployed" is now removed after successful deployment
* **App Deployment:** Show correct bonjour url in terminal after deployment
* **Data Persistance:** All app types now have permissions to write to ``/data`` See [#6](https://github.com/experimental-platform/platform-configure-script/issues/6)
