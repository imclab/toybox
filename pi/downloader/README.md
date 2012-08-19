# Running

```shell
./downloader.rb
```

* You can supply the ```-v``` parameter to get verbose output
* It will drop its stuff in ```/tmp/toybox/```

# Testing with a fake endpoint

You can consider this also API documentation for what the toybox downloader
expects.

```shell
rackup
```

* It expects to find stuff in ```/tmp/trackserver/```

## Requests
### GET /tracks/:id
* Returns a JSON hash of the event/sound settings for the toybox:
 * keys are event labels
 * values are URLs to mp3 downloads

It will look for the file in ```/tmp/trackserver/params[:id].json```

### GET /downloads/:name
* Returns a binary of an mp3

It will look for the file in ```/tmp/trackserver/params[:name]```
