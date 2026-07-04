# Chrony offset calibration procedure


## 1. Let system run for a while

- Let the GPS unit remain powered up for at least an hour to stabilize

- Once the GPS unit is stabilized let the container run for ~15-10 min

- Minimize temperature variations of the system as much as possible

## 2. Grab Chrony Statistics file

Run the below to grab the last 100 lines of the statistics log file

```bash
sudo tail -n 100 /var/lib/docker/volumes/gpsd_chrony_chrony_logs/_data/statistics.log > ./calibration/chrony_statistics.log

```

## 3. Install script dependancies

you will need to have pandas installed within your current env or install pandas system wide

To install system wide: 

```bash
sudo apt get install python3-pandas
```


## 4. Run the chrony_statistics_analyzer.py script

Run the statistics analyzer script

```bash
python ./calibration/chrony_statistics_analyzer.py
```

example output of script:

```bash
Chrony Statistics Summary:
------------------------------
Number of IP Addresses: 1
Time Range: 2025-06-10 23:10:58 to 2025-06-10 23:12:09

Average Estimated Offset by IP:
GPS: 9.36e-02

Median Estimated Offset by IP:
GPS: 9.37e-02
```

Generally we would like to get the average estimated offset as close to zero as possible 

For the above example we will use the Average Estimated Offset of 0.0936 as the offset needed. (Use the specific value from your system)

## 5. Input the offset parameter into chrony.conf 

Bring the container down

```bash
sudo docker compose down
```

Edit the [chrony.conf](../chrony_config/chrony.conf) file line 22, replace the 0.0000 with the offset in seconds.

```bash
refclock SHM 0 refid GPS offset 0.0936 precision 1e-3 poll 0 filter 3
```

Bring the container back up

```bash
sudo docker compose up --detach
```


