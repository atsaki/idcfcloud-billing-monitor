# idcfcloud-billing-monitor
A template to monitor [IDCF Cloud](http://www.idcf.jp/cloud/) billing metrics and post them to [Mackerel](https://mackerel.io)

## How to use

### Deploy to Heroku

Push Heroku Button and fill parameters

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy)

### Scale dyno

You need to scale dyno to make this app work properly.

Set 0 dyno for web and 1 dyno for monitor.

You can set from [dashboard](https://dashboard-next.heroku.com/apps) or heroku command.

```bash
$ heroku ps:scale web=0 monitor=1 --app YOUR_APP_NAME
```
