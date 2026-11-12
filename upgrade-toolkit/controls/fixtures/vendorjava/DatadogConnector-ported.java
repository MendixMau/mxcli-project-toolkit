package datadogconnector.connector;

import com.mendix.core.Core;

public class DatadogConnector {

    static void count(final Metrics.MetricTypes countType, final Long delta, final Map<String, String> tags) {
        final String bucketName = BUCKET_PREFIX + countType.toString().toLowerCase() + ".count";
        tags.putAll(constructDefaultTags());
        Core.metrics().count(bucketName, delta, tags);
    }

    static void time(final Metrics.MetricTypes timerType, final Date startTime, final Map<String, String> tags) {
        final String bucketName = BUCKET_PREFIX + timerType.toString().toLowerCase() + ".time";
        tags.putAll(constructDefaultTags());
        final long time = new Date().getTime() - startTime.getTime();
        Core.metrics().recordTimerMetric(bucketName, time, tags);
    }
    
    static void gauge(final Metrics.MetricTypes gaugeType, final Long value, final Map<String, String> tags) {
        final String bucketName = BUCKET_PREFIX + gaugeType.toString().toLowerCase() + ".gauge";
        tags.putAll(constructDefaultTags());
        Core.metrics().recordGaugeValue(bucketName, value, tags);
    }

    // (jsc) ToDo: when needed, implement remaining metric: sets - https://apidocs.mendix.com/7/runtime/com/mendix/metrics/Metrics.html
}
