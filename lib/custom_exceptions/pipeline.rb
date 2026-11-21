# A clinic pipeline operation the rules do not allow (deleting Ganho /
# Perdido, moving to Perdido without a reason, a second open pass...).
# `key` points at config/locales `pipelines.errors`.
class CustomExceptions::Pipeline < CustomExceptions::Base
  def message
    I18n.t("pipelines.errors.#{@data[:key]}", **@data.except(:key))
  end

  def http_status
    422
  end
end
