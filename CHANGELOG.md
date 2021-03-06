# Changelog

## 2015-11-12

* **System:** Added containerized PulseAudio service
* **Apps:** PulseAudio socket is mounted at `/var/run/pulse/native`
* **Update:** Fixed an issue with checking for updates

## 2015-10-30

* **Apps:** Updated to Dokku 0.4.3
* **Apps:** Redeployment on reboot is now faster
* **Update:** Fixed issue with a warning being shown on successful update

## 2015-10-22

* **System:** Various bugfixes
* **Apps:** Only previously running apps will be rebuilt on reboot
* **System:** Announce SSH and HTTP ports with Bonjour/Avahi
* **System:** Our base Ubuntu image has been cut in size by over 100MB

## 2015-10-16

* **Updates:**: Enabled update of CoreOS image to Protonet's version
* **Updates:**: Fixed issue with update script overwriting itself while still running
* **Apps:** Updated to Dokku 0.4

## 2015-10-01

* **Apps:** They now have full access to ``/dev`` of the host system
* **App List:** Now keeps refreshing even if the platform were down for a short moment

## 2015-09-24

* **Updates:** A live status is now shown during update ([#40](https://github.com/experimental-platform/platform-frontend/pull/40))
* **Apps:** Apps are now started in a priviliged container in order to access hardware apis
* **Logging:** Logging is now at warn level

## 2015-09-17

* **System**: Fix a few issues that could lead to `permission denied` messages
* **Updates**: Fix an issue where container deletion would fail
* **App Deployment**: Deployment error `[8] System error: no such file or directory` should be fixed

## 2015-09-10

* **System**: Fix an issue where the updater in certain situations wrongly announced the availability of an update
* **App List:** Open apps in a new tab


## 2015-09-03

* **USB:** ``/dev/bus/usb`` is now mounted into each app, also ``lsusb`` is available and shows connected devices, serial access isn't working yet because of wrong permissions (see [#20](https://github.com/experimental-platform/platform-configure-script/issues/20))
* **Documentation:** The web frontend now displays a direct link to the Documentation
* **App List:** Correctly detect Dockerfile apps (see [#4](https://github.com/experimental-platform/platform-configure-script/issues/4))
* **App List:** Prefer local (bonjour) url over remote url when opening apps
* **App List:** Changing the name/url of a machine now ensures that all apps get this info and offer the correct app url (fixes [#12](https://github.com/experimental-platform/platform-configure-script/issues/12))
* **Apps:** Apps now receive a correct ``X-Forwarded-Proto`` header (see [#22](https://github.com/experimental-platform/platform-configure-script/issues/22))
* **System:** Fix an issue where docker containers sometimes weren't successfully started after boot

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
